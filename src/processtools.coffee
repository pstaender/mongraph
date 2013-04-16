ObjectId = require('bson').ObjectID
Join = require('join')

# private
# dbhandler
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

sortJoins = (args) ->
  args = Array.prototype.slice.call(args)
  returns = { errors: [] , result: [] }
  for arg in args
    returns.errors.push(arg[0]) if arg[0]
    returns.errors.push(arg[1]) if arg[1]
  returns.errors = if returns.errors.length > 0 then new Error(returns.errors.join(", ")) else null 
  returns.result = if returns.result.length > 0 then returns.result else null
  returns

# extract the constructor name as string
constructorNameOf = (f) ->
  f?.constructor?.toString().match(/function\s+(.+?)\(/)?[1]?.trim() || null

extractCollectionAndId = (s) ->
  { collectionName: parts[0], _id: parts[1] } if (parts = s.split(":"))

_buildQueryFromIdAndCondition = (_id_s, condition) ->
  if _id_s?.constructor is Array
    idCondition = { _id: { $in: _id } }
  else if _id_s
    idCondition = { _id: String(_id_s) }
  else
    return {}
  if typeof condition is 'object' and condition and Object.keys(condition)?.length > 0 then { $and: [ idCondition, condition ] } else idCondition

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
  options.restructure ?= true # do some useful restructure
  options.referenceDocumentID ?= null # document which is our base document, import for where queries
  options.referenceDocumentID = String(options.referenceDocumentID) if options.referenceDocumentID
  options.collection ?= null # distinct collection
  options.where ?= null # query documents
  options.debug = if options.debug then {} else null
  options.stripEmptyItems ?= true
  if options.debug
    options.debug.where ?= []
    # options.debug.cypher ?= []

  unless results instanceof Object
    return cb(new Error('Object is needed for processing'), null, options)
  else unless results instanceof Array
    # put in array to iterate
    results = [ results ]

  # called when all documents loaded
  final = (err) ->
    # [ null, {...}, null, ..., {...}, {...} ] ->  [ {...}, ..., {...}, {...} ]
    # return only path if we have a path here and the option is set to restructre
    # TODO: find a more elegant solution than this
    if options.restructure and path?.length > 0
      results = path
    if options.stripEmptyItems and results?.length > 0
      cleanedResults = []
      for result in results
        cleanedResults.push(result) if result?
      cb(null, cleanedResults, options)
    else
      cb(null, results, options)

  # TODO: if distinct collection

  mongoose = getMongoose()  # get mongoose handler
  graphdb  = getNeo4j()     # get neo4j handler 

  # TODO: extend Path and Relationship objects (nit possible with prototyping here) 

  path = null

  join = Join.create()
  for result, i in results
    do (result, i) ->
      
      ## Node
      if constructorNameOf(result) is 'Node' and result.data?.collection and result.data?._id 
        callback = join.add()
        isReferenceDocument = options.referenceDocumentID is result.data._id
        # skip if distinct collection if differ
        if options.collection and options.collection isnt result.data.collection
          callback(err, results)
        else
          conditions = _buildQueryFromIdAndCondition(result.data._id, unless isReferenceDocument then options.where)
          options.debug.where.push(conditions) if options.debug
          collection = getCollectionByCollectionName(result.data.collection, mongoose)
          collection.findOne conditions, (err, foundDocument) ->
            results[i].document = foundDocument
            callback(err, results)
      
      ## Relationship
      else if constructorNameOf(result) is 'Relationship' and result.data?._from and result.data?._to
        callback = join.add()
        fromAndToJoin = Join.create()
        for point in [ 'from', 'to']
          intermediateCallback = fromAndToJoin.add()
          do (point, intermediateCallback) ->
            {collectionName,_id} = extractCollectionAndId(result.data["_#{point}"])
            isReferenceDocument = options.referenceDocumentID is _id
            # do we have a distinct collection and this records is from another collection? skip it
            if options.collection and options.collection isnt collectionName and not isReferenceDocument 
              # remove relationship from result
              results[i] = null
              intermediateCallback(null,null) #  results will be taken directly from results[i]
            else
              conditions = _buildQueryFromIdAndCondition(_id, unless isReferenceDocument then options.where)
              options.debug.where.push(conditions) if options.debug
              collection = getCollectionByCollectionName(collectionName, mongoose)
              collection.findOne conditions, (err, foundDocument) ->
                if foundDocument and results[i]
                  results[i][point] = foundDocument
                else
                  # remove relationship from result
                  results[i] = null
                intermediateCallback(null,null) # results will be taken directly from results[i]
        fromAndToJoin.when ->
          callback(null, null)

      ## Path
      else if constructorNameOf(result) is 'Path' or constructorNameOf(result.p) is 'Path'
        # in some cases path is in result.p or is directly p
        _p = result.p || result
        results[i].path = Array(_p._nodes.length)
        path = if options.restructure then Array(_p._nodes.length)
        for node, k in _p._nodes
          if node._data?.self
            callback = join.add()
            do (k, callback) ->
              graphdb.getNode node._data.self, (err, foundNode) ->
                if foundNode?.data?._id
                  isReferenceDocument = options.referenceDocumentID is foundNode.data._id
                  collectionName = foundNode.data.collection
                  _id = foundNode.data._id
                  if options.collection and options.collection isnt collectionName and not isReferenceDocument 
                    callback(null, path || results)
                  else
                    conditions = _buildQueryFromIdAndCondition(_id, options.where)
                    options.debug.where.push(conditions) if options.debug
                    collection = getCollectionByCollectionName(collectionName, mongoose)
                    collection.findOne conditions, (err, foundDocument) ->
                      if options.restructure
                        # just push the documents to the result and leave everything else away
                        path[k] = foundDocument
                      else
                        results[i].path[k] = foundDocument
                      callback(null, path || results)
                else
                  if options.restructure
                    path[k] = null
                  else
                    results[i].path[k] = null
                  callback(null, path || results)
      else
        final(new Error("Could not detect given result type"),null)
  
  join.when ->
    {error,result} = sortJoins(arguments)
    final(error, null)
module.exports = {populateResultWithDocuments, getObjectIDAsString, getObjectIDsAsArray, constructorNameOf, getObjectIdFromString, sortOptionsAndCallback, getModelByCollectionName, getCollectionByCollectionName, setMongoose, setNeo4j, extractCollectionAndId, ObjectId}