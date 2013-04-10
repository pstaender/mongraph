ObjectId = require('mongodb').ObjectID
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

loadDocumentsFromNodeArray = (arrayWithNodes, cb) ->
  join = Join.create()
  for node, i in arrayWithNodes
    if node.id
      callbackDocument = join.add()
      node.getDocument callbackDocument
  join.when ->
    # console.log array, b
    err = null
    data = []
    for item in arguments
      err = item[0]
      data.push item[1]
    cb(err,data)

# load record(s) by id from a given array
loadDocumentsFromRelationshipArray = (mongodb, graphResultset, cb) ->
  return cb('Need db connection as argument', null, graphResultset) if constructorNameOf(mongodb) isnt 'NativeConnection'
  return cb('No Array given', null, graphResultset) unless graphResultset?.constructor == Array or (graphResultset = getObjectIDsAsArray(graphResultset)).constructor == Array
  # sort out all non relationship objects
  relations = []
  for relation, i in graphResultset
    relations.push(relation) if constructorNameOf(relation) is 'Relationship'
  # skip it if no relationships (as expected) where found
  # but in case we having another result object
  # we pass it as 3rd argument so that it can be processed some other way
  # TODO: distinguish between relationships, nodes + paths as result
  return cb(null,null,graphResultset) unless relations.length > 0
  join = Join.create()
  # We have to query each record, because they can be stored in different collections
  # TODO: presort collections and do "where in []" queries for each collection
  for relation, i in relations
    do (i, relation) ->
      # Load documents from start and end node
      # will be stored in relation.from and relation.to
      {collectionName, _id} = _extractCollectionAndId(relation.data._to)
      id = getObjectIdFromString(_id)
      callbackTo = join.add()
      mongodb.collection(collectionName).findOne { _id: id } , (err, doc) ->
        relation.to = doc
        callbackTo(err, relation)
      {collectionName, _id} = _extractCollectionAndId(relation.data._from)
      id = getObjectIdFromString(_id)
      callbackFrom = join.add()
      mongodb.collection(collectionName).findOne { _id: id } , (err, doc) ->
        relation.from = doc
        callbackFrom(err, relation)
  join.when ->
    cb(null, relations, graphResultset)

module.exports = {getObjectIDAsString, getObjectIDsAsArray, loadDocumentsFromRelationshipArray, loadDocumentsFromNodeArray, constructorNameOf, getObjectIdFromString, sortOptionsAndCallback}