processtools = require('./processtools')

module.exports = (graphdb, mongodb, options) ->
  # adding document methods on node(s)
  
  # is needed for prototyping
  node = graphdb.createNode()
  Node = node.constructor

  _loadDocumentFromNode = (node, cb) ->
    return cb("No node object given", cb) unless node?._data?.data
    _id =  new processtools.getObjectIdFromString(node.getMongoId())
    collectionName = node.getCollectionName()
    cb("No mongodb connection -> init({..., >>mongodb: mongodbconnection<<, ...", null) unless mongodb and typeof cb is 'function'
    # we need to query the collection natively here
    collection = mongodb.connections[0]?.collection(collectionName) or mongodb.collection(collectionName)
    collection.findOne { _id: _id }, cb

  _loadDocumentFromNodeUrl = (url, cb) ->
    graphdb.getNode url, (err, node) ->
      return cb(err, node) if err 
      _loadDocumentFromNode(node, cb)

  Node::getCollectionName = ->
    # try to extract collection from url (indexed namespace)
    # TODO: better could be via parent document if exists
    # indexed: 'http://localhost:7474/db/data/index/node/people/_id/516123bcc86e28485e000007/755' }
    @_data?.indexed?.match(/\/data\/index\/node\/(.+?)\//)?[1] or @_data?.data.collection

  Node::getMongoId = ->
    # TODO: sometime this needs an extra call
    # _data: { self: 'http://localhost:7474/db/data/node/440' } }
    @_data?.data?._id

  Node::getDocument = (cb) ->
    return cb(null, @document) if @document and typeof cb is 'function'
    # native mongodb call, so we need the objectid as object
    if @_data?.data?._id
      _loadDocumentFromNode @, cb
    else
      _loadDocumentFromNodeUrl @_data?.self, cb
