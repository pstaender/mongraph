ObjectId = require('bson').ObjectID
Join = require('join')

sortOptionsAndCallback = (options, cb) ->
  if typeof options is 'function'
    { options: {}, cb: options }
  else
    { options: options or {}, cb: cb }

# extract the constructor name as string
constructorNameOf = (f) ->
  f?.constructor?.toString().match(/function\s+(.+?)\(/)[1]?.trim()

_extractCollectionAndId = (s) ->
  { collectionName: parts[0], _id: parts[1] } if (parts = s.split(":"))

# extract id as string from a mixed argument
getObjectIDAsString = (obj) ->
  if typeof obj is 'string'
    obj
  else if typeof obj is 'object'
    (String) obj._id or obj
  else
    ''

getObjectIdFromString = (s) ->
  new ObjectId(s)

# extract id's from a mixed type
getObjectIDsAsArray = (mixed) ->
  ids = []
  if mixed?.constructor == Array
    for item in mixed
      ids.push(id) if id = getObjectIDAsString(item)
  else
    ids = [ getObjectIDAsString(mixed) ]
  ids

loadDocumentsWithConditions = (documents, conditions, options, cb) ->
  {options,cb} = sortOptionsAndCallback(options,cb)
  mongoose = options.mongodb
  collections = {}
  for doc in documents
    collectionName = doc.constructor.collection.name
    collections[collectionName] ?= []
    collections[collectionName].push(doc)

  cb(new Error('Not implemented yet'), null)


loadDocumentsFromNodeArray = (result, options, cb) ->
  {options, cb} = sortOptionsAndCallback(options,cb)
  mongoose = options.mongodb
  arrayWithNodes = result[0]?.nodes
  return cb(new Error("Couldn't find any nodes to process"), result) unless arrayWithNodes
  join = Join.create()
  for node, i in arrayWithNodes
    if node.id
      callbackDocument = join.add()
      node.getDocument callbackDocument
  join.when ->
    err = null
    data = []
    for item in arguments
      err = item[0]
      data.push item[1]
    if options.where
      loadDocumentsWithConditions(data, options.where, options, cb)
      # console.log ids
      # console.log 'where', { $and: [ { _id: { $in: ids } } , options.where ] }
      # mongoose.find({ $and: [ { _id: { $in: ids } } , options.where ] }, cb)
    else
      cb(err,data)

# TODO: Merge relationships and node loading documents together
# TODO: shrink redundant code
loadDocumentsFromArray = (array, options, cb) ->
  {options, cb} = sortOptionsAndCallback(options, cb)
  mongoose = options.mongodb
  specificCollection = null
  # only sort with collection if we have one direction and a collection given
  if options.direction isnt 'both' and options.collection
    specificCollection = options.collection or null
  join = Join.create()
  results = []
  for record, i in array
    do (i, record) ->
      # Ensure that we have a relationship record here
      if record.data._to and record.data._from
        relation = record
        doPush = false
        # Load documents from start and end node
        # will be stored in relation.from and relation.to

        # to side
        {collectionName, _id} = _extractCollectionAndId(relation.data._to)
        if not specificCollection or ( specificCollection is collectionName and options.direction = 'incoming' )
          id = getObjectIdFromString(_id)
          condition = if options.where and options.direction isnt 'incoming' then { $and: [ { _id: id } , options.where ] } else { _id: id }
          callbackTo = join.add()
          doPush = true
          mongoose.collection(collectionName).findOne condition , (err, doc) ->
            relation.to = doc
            callbackTo(err, relation)

        # from side
        {collectionName, _id} = _extractCollectionAndId(relation.data._from)
        if not specificCollection or specificCollection is collectionName and options.direction = 'outgoing'
          id = getObjectIdFromString(_id)
          condition = if options.where and options.direction isnt 'outgoing' then { $and: [ { _id: id } , options.where ] } else { _id: id }
          callbackFrom = join.add()
          doPush = true
          mongoose.collection(collectionName).findOne condition , (err, doc) ->
            relation.from = doc
            callbackFrom(err, relation)

        results.push(relation) if doPush
      else
        cb(new Error('We have no relationship here'), null)
  join.when ->
    # sort out results that do not fit the where query
    if options.where
      finalResults = []
      for result in results
        finalResults.push(result) if result.from and result.to
    else
      finalResults = results
    cb(null, finalResults, options.graphResultset)

# load record(s) by id from a given array
loadDocumentsFromRelationshipArray = (graphResultset, options, cb) ->
  {options, cb} = sortOptionsAndCallback(options,cb)
  mongoose = options.mongodb
  return cb(new Error('Need db connection as argument'), null, graphResultset) if constructorNameOf(mongoose) isnt 'NativeConnection'
  return cb(new Error('No Array given'), null, graphResultset) unless graphResultset?.constructor == Array or (graphResultset = getObjectIDsAsArray(graphResultset)).constructor == Array
  # sort out all non relationship objects
  relations = []
  for relation, i in graphResultset
    relations.push(relation) if constructorNameOf(relation) is 'Relationship'
  # skip it if no relationships (as expected) where found
  # but in case we having another result object
  # we pass it as 3rd argument so that it can be processed some other way
  # TODO: distinguish between relationships, nodes + paths as result
  return cb(null,null,graphResultset) unless relations.length > 0
  # We have to query each record, because they can be stored in different collections
  # TODO: presort collections and do "where in []" queries for each collection
  options.graphResultset = graphResultset
  loadDocumentsFromArray(relations, options, cb)
  

getModelByCollectionName = (collectionName, mongoose) ->
  if constructorNameOf(mongoose) is 'Mongoose'
    models = mongoose.models
  else unless mongoose
    return null
  else
    # we assume that we have mongoose.models here
    models = mongoose
  name = null
  for nameOfModel, i of models
    # iterate through models and find the corresponding collection and modelname
    if collectionName is models[nameOfModel].collection.name
      name = models[nameOfModel].modelName
  name


module.exports = {getObjectIDAsString, getObjectIDsAsArray, loadDocumentsFromRelationshipArray, loadDocumentsFromNodeArray, constructorNameOf, getObjectIdFromString, sortOptionsAndCallback, getModelByCollectionName}