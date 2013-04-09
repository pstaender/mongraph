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

# load record(s) by id from a given array
loadDocumentsFromRelationshipArray = (mongodb, array, cb) ->
  return cb('Need db connection as argument', null) if constructorNameOf(mongodb) isnt 'NativeConnection'
  return cb('No Array given', null) unless array?.constructor == Array or (array = getObjectIDsAsArray(array)).constructor == Array
  # sort out all non relationship objects
  relations = []
  documents = []
  for relation, i in array
    relations.push(relation) if constructorNameOf(relation) is 'Relationship'
  # cancel if no relationships found
  return cb(null,null) unless relations.length > 0
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
    cb(null, relations, documents)

module.exports = {getObjectIDAsString, getObjectIDsAsArray, loadDocumentsFromRelationshipArray, constructorNameOf, getObjectIdFromString, sortOptionsAndCallback}