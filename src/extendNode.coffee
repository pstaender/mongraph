processtools = require('./processtools')

module.exports = (graphdb, mongodb, options) ->
  # adding document methods on node(s)
  
  # is needed for prototyping
  node = graphdb.createNode()
  Node = node.constructor

  Node::getCollectionName = ->
    # try to extract collection from url (indexed namespace)
    # TODO: better could be via parent document if exists
    # indexed: 'http://localhost:7474/db/data/index/node/people/_id/516123bcc86e28485e000007/755' }
    @_data?.indexed?.match(/\/data\/index\/node\/(.+?)\//)?[1]

  Node::getMongoId = ->
    @_data?.data?._id

  Node::getDocument = (cb) ->
    return cb(null, @document) if @document and typeof cb is 'function'
    # native mongodb call, so we need the objectid as object
    _id = new processtools.getObjectIdFromString(@getMongoId())
    collectionName = @getCollectionName()
    cb("No mongodb connection -> init({..., >>mongodb: mongodbconnection<<, ...", null) unless mongodb and typeof cb is 'function'
    mongodb.collection(collectionName).findOne { _id: _id }, cb