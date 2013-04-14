# ### Extend Neo4j
#
# This models extends the Node object of the neo4j module with:
# * get the collectionname and _if of the mongodb document
# * load the corresponding document from mongodb

processtools = require('./processtools')

module.exports = (graphdb, mongoose, options) ->
  #### Adding document methods on node(s)

  # Check that we don't override existing functions
  if options.overwriteProtypeFunctions isnt true
    node = graphdb.createNode()
    for functionName in [ 'getDocument', 'getMongoId', 'getCollectionName' ]
      throw new Error("Will not override neo4j::Node.prototype.#{functionName}") unless typeof node.constructor::[functionName] is 'undefined'

  
  # Is needed for prototyping
  node = graphdb.createNode()
  Node = node.constructor

  #### Loads corresponding document from given node object
  _loadDocumentFromNode = (node, cb) ->
    return cb("No node object given", cb) unless node?._data?.data
    _id =  new processtools.getObjectIdFromString(node.getMongoId())
    collectionName = node.getCollectionName()
    cb(new Error("No cb given", null)) if typeof cb isnt 'function'
    # we need to query the collection natively here
    # TODO: find a more elegant way to access models instead of needing the "registerModels" way...
    collection = processtools.getCollectionByCollectionName(collectionName, mongoose)
    collection.findOne { _id: _id }, cb

  #### Loads corresponding document from given neo4j url 
  _loadDocumentFromNodeUrl = (url, cb) ->
    graphdb.getNode url, (err, node) ->
      return cb(err, node) if err 
      _loadDocumentFromNode(node, cb)

  #### Returns the name of the collection from indexed url or from stored key/value
  Node::getCollectionName = ->
    # try to extract collection from url (indexed namespace)
    # TODO: better could be via parent document if exists
    # indexed: 'http://localhost:7474/db/data/index/node/people/_id/516123bcc86e28485e000007/755' }
    @_data?.indexed?.match(/\/data\/index\/node\/(.+?)\//)?[1] or @_data?.data.collection

  #### Returns the mongodb document _id from stored key/value
  Node::getMongoId = ->
    # TODO: sometimes node doen't include the data -> would need extra call
    # e.g.: _data: { self: 'http://localhost:7474/db/data/node/X' } }
    @_data?.data?._id# or null

  #### Loads the node's corresponding document from mongodb
  Node::getDocument = (cb) ->
    return cb(null, @document) if @document and typeof cb is 'function'
    # Native mongodb call, so we need the objectid as object
    if @_data?.data?._id
      _loadDocumentFromNode @, cb
    else
      _loadDocumentFromNodeUrl @_data?.self, cb
