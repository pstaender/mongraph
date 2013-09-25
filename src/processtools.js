var ObjectId = require('bson').ObjectID
  , Join = require('join');

var mongooseHandler = null; // will be set initially

// extract the constructor name as string
var constructorNameOf = function(f) {
  if (typeof f !== 'undefined')
    return f.constructor.toString().match(/function\s+(.+?)\(/)[1].trim();
  else
    return null;
}

var extractCollectionAndId = function(s) {
  var parts = s.split(":");
  return (parts) ? { collectionName: parts[0], _id: parts[1] } : null; 
}

// extract id as string from a mixed argument
var getObjectIDAsString = function(obj) {
  if (typeof obj === 'string')
    return obj;
  else if (typeof obj === 'object')
    return String(obj._id) || String(obj);
  else
    return '';
}

var getObjectIdFromString = function (s) {
  new ObjectId(s);
}

var getModelByCollectionName = function(collectionName) {
  var models = null
    , name = null;
  if (constructorNameOf(mongooseHandler) === 'Mongoose')
    models = mongooseHandler.models;
  else if (!mongooseHandler)
    return null;
  else
    // we assume that we have mongoose.models here
    models = mongoose;
  modelsArray = Object.keys(models);
  for (var i=0; i < modelsArray.length; i++) {
    var nameOfModel = modelsArray[i];
    // iterate through models and find the corresponding collection and modelname
    if (collectionName === models[nameOfModel].collection.name)
      name = models[nameOfModel];
  }
  return name;
}

var getModelNameByCollectionName = function(collectionName) {
  var collection = getModelByCollectionName(collectionName);
  return (collection) ? collection.modelName : '';
}

var getCollectionByCollectionName = function(collectionName) {
  var modelName = getModelNameByCollectionName(collectionName);
  return mongooseHandler.models[modelName] || mongooseHandler.connections[0].collection(collectionName) || mongooseHandler.collection(collectionName);
}

module.exports = {
  init: function(mongoose) {
    if (constructorNameOf(mongoose) !== 'Mongoose')
      throw Error('You need to pass a mongoose handler to init processtools');
    mongooseHandler = mongoose;
    return module.exports;
  },
  ObjectId: ObjectId,
  constructorNameOf: constructorNameOf,
  extractCollectionAndId: extractCollectionAndId,
  getObjectIDAsString: getObjectIDAsString,
  getObjectIdFromString: getObjectIdFromString,
  getModelByCollectionName: getModelByCollectionName,
  getModelNameByCollectionName: getModelNameByCollectionName,
  getCollectionByCollectionName: getCollectionByCollectionName 
}

// # Iterates through the neo4j's resultset and attach documents from mongodb
// # =====
// #
// # Currently we having three different of expected Objects: Node, Relationship and Path
// # TODO: maybe split up to submethods for each object type
// # TODO: reduce mongodb queries by sorting ids to collection(s) and query them once per collection with $in : [ ids... ] ...

// populateResultWithDocuments = (results, options, cb) ->
//   {options, cb} = sortOptionsAndCallback(options,cb)
  
//   options.count ?= false
//   options.restructure ?= true # do some useful restructure
//   options.referenceDocumentID ?= null # document which is our base document, import for where queries
//   options.referenceDocumentID = String(options.referenceDocumentID) if options.referenceDocumentID
//   options.relationships ?= {}
//   options.collection ?= null # distinct collection
//   options.where?.document ?= null # query documents
//   options.debug?.where ?= []
//   options.stripEmptyItems ?= true
  

//   unless results instanceof Object
//     return cb(new Error('Object is needed for processing'), null, options)
//   else unless results instanceof Array
//     # put in array to iterate
//     results = [ results ]

//   # Finally called when *all* documents are loaded and we can pass the result to cb
//   final = (err) ->
//     # [ null, {...}, null, ..., {...}, {...} ] ->  [ {...}, ..., {...}, {...} ]
//     # return only path if we have a path here and the option is set to restructre
//     # TODO: find a more elegant solution than this
//     if options.restructure and path?.length > 0
//       results = path
//     if options.stripEmptyItems and results?.length > 0
//       cleanedResults = []
//       for result in results
//         cleanedResults.push(result) if result?
//       cb(null, cleanedResults, options) if typeof cb is 'function'
//     else
//       cb(null, results, options) if typeof cb is 'function'

//   # TODO: if distinct collection

//   mongoose = getMongoose()  # get mongoose handler
//   graphdb  = getNeo4j()     # get neo4j handler


//   # TODO: extend Path and Relationship objects (nit possible with prototyping here) 

//   path = null

//   join = Join.create()
//   for result, i in results
//     do (result, i) ->
      
//       # ### NODE
//       if constructorNameOf(result) is 'Node' and result.data?._collection and result.data?._id 
//         callback = join.add()
//         isReferenceDocument = options.referenceDocumentID is result.data._id
//         # skip if distinct collection if differ
//         if options.collection and options.collection isnt result.data._collection
//           callback(err, results)
//         else
//           conditions = _buildQueryFromIdAndCondition(result.data._id, unless isReferenceDocument then options.where?.document)
//           options.debug?.where.push(conditions)
//           collection = getCollectionByCollectionName(result.data._collection, mongoose)
//           collection.findOne conditions, (err, foundDocument) ->
//             results[i].document = foundDocument
//             callback(err, results)
      
//       # ### RELATIONSHIP
//       else if constructorNameOf(result) is 'Relationship' and result.data?._from and result.data?._to
//         # TODO: trigger updateRelationships for both sides if query was about and option is set to
//         callback = join.add()
//         fromAndToJoin = Join.create()
//         # Extend out Relationship object with additional methods
//         extendRelationship(result)
//         for point in [ 'from', 'to']
//           intermediateCallback = fromAndToJoin.add()
//           do (point, intermediateCallback) ->
//             {collectionName,_id} = extractCollectionAndId(result.data["_#{point}"])
//             isReferenceDocument = options.referenceDocumentID is _id
//             # do we have a distinct collection and this records is from another collection? skip if so
//             if options.collection and options.collection isnt collectionName and not isReferenceDocument 
//               # remove relationship from result
//               results[i] = null
//               intermediateCallback(null,null) #  results will be taken directly from results[i]
//             else
//               conditions = _buildQueryFromIdAndCondition(_id, unless isReferenceDocument then options.where?.document)
//               options.debug?.where?.push(conditions)
//               collection = getCollectionByCollectionName(collectionName, mongoose)
//               collection.findOne conditions, (err, foundDocument) ->
//                 if foundDocument and results[i]
//                   results[i][point] = foundDocument
//                 else
//                   # remove relationship from result
//                   results[i] = null
//                 intermediateCallback(null,null) # results will be taken directly from results[i]
//         fromAndToJoin.when ->
//           callback(null, null)

//       # ### PATH
//       else if constructorNameOf(result) is 'Path' or constructorNameOf(result[options.processPart]) is 'Path' or  constructorNameOf(result.path) is 'Path'
//         # Define an object identifier for processPart
//         _p = result[options.processPart] || result.path || result
//         extendPath(_p)
//         results[i].path = Array(_p._nodes.length)
//         path = if options.restructure then Array(_p._nodes.length)
//         for node, k in _p._nodes
//           if node._data?.self
//             callback = join.add()
//             do (k, callback) ->
//               graphdb.getNode node._data.self, (err, foundNode) ->
//                 if foundNode?.data?._id
//                   isReferenceDocument = options.referenceDocumentID is foundNode.data._id
//                   collectionName = foundNode.data._collection
//                   _id = foundNode.data._id
//                   if options.collection and options.collection isnt collectionName and not isReferenceDocument 
//                     callback(null, path || results)
//                   else
//                     conditions = _buildQueryFromIdAndCondition(_id, options.where?.document)
//                     options.debug?.where?.push(conditions)
//                     collection = getCollectionByCollectionName(collectionName, mongoose)
//                     collection.findOne conditions, (err, foundDocument) ->
//                       if options.restructure
//                         # just push the documents to the result and leave everything else away
//                         path[k] = foundDocument
//                       else
//                         results[i].path[k] = foundDocument
//                       callback(null, path || results)
//                 else
//                   if options.restructure
//                     path[k] = null
//                   else
//                     results[i].path[k] = null
//                   callback(null, path || results)
//       else
//         final(new Error("Could not detect given result type"),null)
  
//   # ### If all callbacks are fulfilled 

//   join.when ->
//     {error,result} = sortJoins(arguments)
//     final(error, null)

// module.exports = {
//   populateResultWithDocuments,
//   getObjectIDAsString,
//   getObjectIDsAsArray,
//   constructorNameOf,
//   getObjectIdFromString,
//   sortOptionsAndCallback,
//   sortAttributesAndCallback,
//   sortTypeOfRelationshipAndOptionsAndCallback,
//   getModelByCollectionName,
//   getModelNameByCollectionName,
//   getCollectionByCollectionName,
//   setMongoose,
//   setNeo4j,
//   extractCollectionAndId,
//   ObjectId }
