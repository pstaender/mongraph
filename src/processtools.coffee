ObjectId = require('bson').ObjectID
Join = require('join')

# private
mongoose = null
neo4j    = null

setMongoose = (mongooseHandler) -> mongoose = mongooseHandler
getMongoose = -> mongoose

setNeo4j = (neo4jHandler) -> neo4j = neo4jHandler
getNeo4j = -> neo4j

sortOptionsAndCallback = (options, cb) ->
  if typeof options is 'function'
    { options: {}, cb: options }
  else
    { options: options or {}, cb: cb }

# extract the constructor name as string
constructorNameOf = (f) ->
  f?.constructor?.toString().match(/function\s+(.+?)\(/)?[1]?.trim() || null

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

# TODO: make simpler queries (to neo4j + mongodb) -> only by id's
loadDocumentsWithConditions = (documents, conditions, options, cb) ->
  {options,cb} = sortOptionsAndCallback(options,cb)
  # collections with ids
  collectionIds = {}
  # ids with collection
  allIds = {}
  # Sort ids + collections
  for doc in documents
    collectionName = doc.constructor.collection.name
    collectionIds[collectionName] ?= []
    collectionIds[collectionName].push(doc._id)
    allIds[doc._id] = collectionName
  # Do one (faster) query if we have a distinct collection
  # if we have documents found for this collection
  if options.collection and collectionIds[options.collection]?.length > 0
    condition = { $and: [ { _id: { $in: collectionIds[options.collection] } } , conditions ] }
    collection = getCollectionByCollectionName(options.collection, mongoose)
    return collection.find condition, cb
  join = Join.create()
  # get all documents by ids
  for id of allIds
    collectionName = allIds[id]
    collection = getCollectionByCollectionName(collectionName, mongoose)
    do (collection, id) ->
      callback = join.add()
      condition = { $and: [ { _id: id }, conditions ] }
      collection.find condition, callback
  join.when ->
    errs = []
    docs = []
    for result in arguments
      errs.push(result[0]?.message or result[0]) if result[0] # if error
      if result[1] # if doc found
        for record in result[1]
          docs.push(record) 
      
    if errs.length > 0
      cb(new Error(errs.join(", ")), docs) 
    else
      cb(null, docs)


loadDocumentsFromNodeArray = (result, options, cb) ->
  {options, cb} = sortOptionsAndCallback(options,cb)
  arrayWithNodes = result[0]?.nodes
  return cb(new Error("Couldn't find any nodes to process"), result) unless arrayWithNodes
  # Load corresponding documents to all nodes... no other way, yet
  # TODO: do a more economical query to graphdb or mongodb to get the document id
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
    else
      cb(err,data,options)

# TODO: Merge relationships and node loading documents together
# TODO: shrink redundant code
loadDocumentsFromArray = (array, options, cb) ->
  {options, cb} = sortOptionsAndCallback(options, cb)
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
          collection = getCollectionByCollectionName(collectionName, mongoose)
          collection.findOne condition , (err, doc) ->
            relation.to = doc
            callbackTo(err, relation)

        # from side
        {collectionName, _id} = _extractCollectionAndId(relation.data._from)
        if not specificCollection or specificCollection is collectionName and options.direction = 'outgoing'
          id = getObjectIdFromString(_id)
          condition = if options.where and options.direction isnt 'outgoing' then { $and: [ { _id: id } , options.where ] } else { _id: id }
          callbackFrom = join.add()
          doPush = true
          collection = getCollectionByCollectionName(collectionName, mongoose)
          collection.findOne condition , (err, doc) ->
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
    cb(null, finalResults, options)

# load record(s) by id from a given array
loadDocumentsFromRelationshipArray = (graphResultset, options, cb) ->
  {options, cb} = sortOptionsAndCallback(options,cb)
  # return cb(new Error('Need db connection as argument'), null, graphResultset) if constructorNameOf(mongoose) isnt 'NativeConnection'
  return cb(new Error('No Array given'), null, options) unless graphResultset?.constructor == Array or (graphResultset = getObjectIDsAsArray(graphResultset)).constructor == Array
  # sort out all non relationship objects
  relations = []
  for relation, i in graphResultset
    relations.push(relation) if constructorNameOf(relation) is 'Relationship'
  # TODO: also implement a options.count for after querying mongodb
  return cb(null,relations.length,options) if options.countRelationships
  # skip it if no relationships (as expected) where found
  # but in case we having another result object
  # we pass it as 3rd argument so that it can be processed some other way
  # TODO: distinguish between relationships, nodes + paths as result
  return cb(null,null,options) unless relations.length > 0
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

getCollectionByCollectionName = (collectionName, mongoose) ->
  modelName = getModelByCollectionName(collectionName, mongoose)
  mongoose.models[modelName] or mongoose.connections[0]?.collection(collectionName) or mongoose.collection(collectionName)


populateResultWithDocuments = (results, options, cb) ->
  # TODO: reduce mongodb queries by sorting ids to collection(s)
  # and query them once per collection with $in : [ ids... ] ...
  {options, cb} = sortOptionsAndCallback(options,cb)
  options.count ?= false
  unless results instanceof Object
    return cb(new Error('Object is needed for processing'), null, options)
  else unless results instanceof Array
    # put in array to iterate
    results = [ results ]
  # else if constructorNameOf(results[0]) is 'Path'
  #   results = [ results[0].p ]

  # called when all documents loaded
  final = (err, results) ->
    cb(null, results, options)

  mongoose = getMongoose()  # get mongoose handler
  graphdb  = getNeo4j()     # get neo4j handler 

  todo = 0
  done = 0

  for result, i in results
    do (result, i) ->
      ## Node
      if constructorNameOf(result) is 'Node' and result.data?.collection and result.data?._id
        todo++
        conditions = { _id: result.data._id }
        collection = getCollectionByCollectionName(result.data.collection, mongoose)
        collection.findOne conditions, (err, foundDocument) ->
          done++
          results[i].document = foundDocument
          final(err, results) if done >= todo
      ## Relationship
      else if constructorNameOf(result) is 'Relationship' and result.data?._from and result.data?._to
        todo++ # from
        todo++ # to
        #### from
        {collectionName,_id} = _extractCollectionAndId(result.data._from)
        conditions = { _id: _id }
        collection = getCollectionByCollectionName(collectionName, mongoose)
        collection.findOne conditions, (err, foundDocument) ->
          done++
          results[i].from = foundDocument
          final(err, results) if done >= todo
        #### to
        {collectionName,_id} = _extractCollectionAndId(result.data._to)
        conditions = { _id: _id }
        collection = getCollectionByCollectionName(collectionName, mongoose)
        collection.findOne conditions, (err, foundDocument) ->
          done++
          results[i].to = foundDocument
          final(err, results) if done >= todo
      else if constructorNameOf(result.p) is 'Path'
        results[i].path = Array(result.p._nodes.length)
        for node, k in result.p._nodes
          if node._data?.self
            todo++
            do (k) ->
              graphdb.getNode node._data.self, (err, foundNode) ->
                if foundNode?.data?._id
                  # console.log foundNode?.data?._id, k
                  collectionName = foundNode.data.collection
                  _id = foundNode.data._id
                  conditions = { _id: _id }
                  collection = getCollectionByCollectionName(collectionName, mongoose)
                  collection.findOne conditions, (err, foundDocument) ->
                    done++
                    results[i].path[k] = foundDocument
                    final(null, results) if done >= todo
                else
                  done++
                  results[i].path[k] = null
                  final(null, results) if done >= todo
      else
        final(new Error("Could not detect given result type"),null)

module.exports = {populateResultWithDocuments, getObjectIDAsString, getObjectIDsAsArray, loadDocumentsFromRelationshipArray, loadDocumentsFromNodeArray, constructorNameOf, getObjectIdFromString, sortOptionsAndCallback, getModelByCollectionName, getCollectionByCollectionName, setMongoose, setNeo4j}