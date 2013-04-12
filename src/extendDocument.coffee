# ### Extend Document
#
# This models extends the mongodb/mongoose Document with:
# * allows creating, deleting and querying all kind of incoming and outgoing relationships
# * native queries on neo4j with option to load Documents by default
# * connects each Document with corresponding Node in neo4j
#
# TODO: check that we always get Documents as mongoose models

processtools = require('./processtools')

module.exports = (mongoose, graphdb, globalOptions) ->

  Document = mongoose.Document

  node = graphdb.createNode()

  #### Can be used to make native queries on neo4j
  # TODO: helpful / best practice? not sure... -> instead you should query directly via neo4j module
  Document::_graphdb = {
    # handler for using for custom queries
    db: graphdb
  }

  #### Private method to query neo4j directly
  #### options -> see Document::queryRelationships
  _queryGraphDB = (cypher, options = {}, cb) ->
    options.loadDocuments ?= true
    # TODO: "mongoose.connection" doesn't work as expected
    # but options.mongoose native connection is mandatory
    # so we must ensure that we always attach a connection from document
    # TODO: type check
    return cb("Set 'option.mongodbConnection' with a NativeConnection to process query", null) unless processtools.constructorNameOf(options.mongodbConnection) is 'NativeConnection'
    graphdb.query cypher, (err, map) ->
      # add query to error if we have one, better for debugging
      # TODO: remove later or use an option switch ?!
      err.query = cypher if err
      if options.loadDocuments and map?.length > 0
        # extract from result
        data = for result in map
          if options.processPart
            result[options.processPart]
          else
            # return first first property otherwise
            result[Object.keys(result)[0]]
        if processtools.constructorNameOf(data[0]) is 'Relationship'
          processtools.loadDocumentsFromRelationshipArray options.mongodbConnection, data, cb
        # TODO: distinguish between 'Path', 'Node' etc ...
        else
          processtools.loadDocumentsFromNodeArray data, cb
      else
        # prevent `undefined is not a function` if no cb is given
        cb(err, map) if typeof cb is 'function'

  #### Loads the equivalent node to this Document 
  Document::findEquivalentNode = (cb, doCreateIfNotExists = false) ->
    doc = @
    collectionName = doc.constructor.collection.name
    id = processtools.getObjectIDAsString(doc)
    # Find equivalent node in graphdb
    # TODO: cache existing node
    # TODO: replace with graphdb.getNodeById,
    # but for that we need always the node id stored in this document (problem with mongoose plugin)
    graphdb.getIndexedNode collectionName, '_id', id, (foundErr, node) ->
      node.document = doc if node# cache  
      if doCreateIfNotExists and not node
        # create new node and save
        node = graphdb.createNode( _id: id, collection: collectionName )
        if globalOptions.storeDocumentInGraphDatabase
          # Store mongodb record in graphdb as well
          # e.g. { getters: true }
          # see -> http://mongoosejs.com/docs/api.html#document_Document-toObject
          node.data = doc.toObject(globalOptions.storeDocumentInGraphDatabase)
        node.save (saveErr) ->
          # index node
          return cb(saveErr, node) if saveErr
          node.index collectionName, '_id', id, (indexErr) ->
            # cache node, not implemented
            node.document = doc # cache
            return cb(indexErr, node)
      else        
        cb(null, node) if typeof cb is 'function'

  #### Finds or create equivalent Node to this Document
  Document::findOrCreateEquivalentNode = (cb) -> @findEquivalentNode(cb, true)
  
  # Recommend to use this method instead of `findOrCreateEquivalentNode`
  # shortcutmethod -> findOrCreateEquivalentNode
  Document::getNode = Document::findOrCreateEquivalentNode


  #### Finds and returns id of corresponding Node
  # Faster, because it returns directly from document if stored (see -> mongraphMongoosePlugin)
  Document::getNodeId = (cb) ->
    if @_node_id
      cb(null, @_node_id)
    else
      @getNode cb

  #### Creates a relationship from this Document to a given document
  Document::createRelationshipTo = (doc, kindOfRelationship, attributes = {}, cb) ->
    # assign cb + attribute arguments
    if typeof attributes is 'function'
      cb = attributes
      attributes = {}
    # Is needed to load the records from mongodb
    # TODO: Currently we have to store these information redundant because
    # otherwise we would have to request each side for it's represantive node
    # seperately to get the information wich namespace/collection the mongodb records is stored
    # -->  would increase requests to neo4j
    if globalOptions.relationships.storeIDsInRelationship
      attributes._to   ?= doc.constructor.collection.name + ":" + (String) doc._id
      attributes._from ?= @constructor.collection.name    + ":" + (String) @._id
     
    if globalOptions.relationships.storeTimestamp
      attributes._created_at ?= Math.floor(Date.now()/1000) 

    # Get both nodes: "from" node (this document) and "to" node (given as 1st argument)
    @findOrCreateEquivalentNode (fromErr, from) ->
      doc.findOrCreateEquivalentNode (toErr, to) ->
        if from and to
          from.createRelationshipTo to, kindOfRelationship, attributes, cb
        else
          cb(fromErr or toErr, null) if typeof cb is 'function'
  
  #### Creates an incoming relationship from a given Documents to this Document
  Document::createRelationshipFrom = (doc, kindOfRelationship, attributes = {}, cb) ->
    # alternate directions: doc -> this
    doc.createRelationshipTo(@, kindOfRelationship, attributes, cb)

  #### Creates a bidrectional relationship between two Documents
  Document::createRelationshipBetween = (doc, kindOfRelationship, attributes = {}, cb) ->
    # both directions
    self = @
    found = []
    @createRelationshipTo doc, kindOfRelationship, attributes, (err, first) ->
      return cb(err) if err
      found.push(first)
      doc.createRelationshipTo self, kindOfRelationship, attributes, (err, second) ->
        return cb(err) if err
        found.push(second)
        cb(err, found) if typeof cb is 'function'

  #### Query the graphdb with cypher, current Document is not relevant for the query 
  Document::queryGraph = (chypherQuery, options, cb) ->
    doc = @
    {options, cb} = processtools.sortOptionsAndCallback(options,cb)
    options.mongodbConnection = doc.db
    _queryGraphDB(chypherQuery, options, cb)

  #### Allows extended querying to the graphdb and loads found Documents
  #### (is used by many methods for loading incoming + outgoing relationships) 
  # @param kindOfRelationship = '*' (any relationship you can query with cypher, e.g. KNOW, LOVE|KNOW ...)
  # @param options = {}
  # (first value is default)
  # * direction (both|incoming|outgoing)
  # * action: (RETURN|DELETE|...) (all other actions wich can be used in cypher)
  # * processPart: (relationship|path|...) (depends on the result you expect from our query)
  # * loadDocuments: (true|false)
  # * endNode: '' (can be a node object or an nodeID)
  Document::queryRelationships = (kindOfRelationship, options, cb) ->
    _s = require('underscore.string')
    # options can be a cypher query as string
    options = { query: options } if typeof options is 'string'
    {options, cb} = processtools.sortOptionsAndCallback(options,cb)
    # build query from options
    kindOfRelationship ?= '*'
    kindOfRelationship = if /^[*:]{1}$/.test(kindOfRelationship) or not kindOfRelationship then '' else ':'+kindOfRelationship
    options.direction ?= 'both'
    options.action ?= "RETURN"
    options.processPart ?= "relation"
    # endNode can be string or node object
    options.endNode ?= ""
    options.endNode = endNode.id if typeof endNode is 'object'
    options.loadDocuments ?= true
    doc = @
    id = processtools.getObjectIDAsString(doc)
    @getNode (nodeErr, fromNode) ->
      cypher = """
                START a = node(%(id)s)%(endNode)s
                MATCH (a)%(incoming)s[relation%(relation)s]%(outgoing)s(b)
                %(action)s %(processPart)s;
               """
      cypher = _s.sprintf cypher,
        id:             fromNode.id
        incoming:       if options.direction is 'incoming' then '<-' else '-'
        outgoing:       if options.direction is 'outgoing' then '->' else '-'
        relation:       kindOfRelationship
        action:         options.action.toUpperCase()
        processPart:    options.processPart
        endNode:        if options.endNode then ", b = node(#{options.endNode})" else ''
      if options.query
        # take query from options and discard build query
        cypher = query
      if options.dontExecute
        cb({ message: "`dontExecute` options is set", query: cypher, options: options }, null)
      else
        options.mongodbConnection ?= doc.db
        _queryGraphDB(cypher, options, cb)

  #### Loads incoming and outgoing relationships
  Document::allRelationships = (kindOfRelationship, cb) ->
    @queryRelationships(kindOfRelationship, { direction: 'both' }, cb)

  #### Loads incoming relationships
  Document::incomingRelationships = (kindOfRelationship, cb) ->
    @queryRelationships(kindOfRelationship, { direction: 'incoming' }, cb)

  #### Loads outgoing relationships
  Document::outgoingRelationships = (kindOfRelationship, cb) ->
    @queryRelationships(kindOfRelationship, { direction: 'outgoing' }, cb)
  
  #### Remove outgoing relationships to a specific Document
  Document::removeRelationshipsTo = (doc, kindOfRelationship, cb, direction = 'outgoing') ->
    from = @
    doc.getNode (nodeErr, endNode) ->
      return cb(nodeErr, endNode) if nodeErr
      from.queryRelationships kindOfRelationship, { direction: direction, action: 'DELETE', endNode: endNode.id }, cb

  #### Removes incoming relationships to a specific Document
  # TODO: testing
  Document::removeRelationshipsFrom = (doc, kindOfRelationship, cb, direction = 'incoming') ->
    @removeRelationshipsTo(doc, kindOfRelationship, cb, direction)

  #### Removes incoming ad outgoing relationships between two Documents
  # TODO: testing
  Document::removeRelationshipsBetween = (doc, kindOfRelationship, cb, direction = 'both') ->
    @removeRelationshipsTo(doc, kindOfRelationship, cb, direction)

  #### Removes incoming and outgoing relationships to all Documents (useful bevor deleting a node/document)
  # TODO: testing
  Document::removeRelationships = (kindOfRelationship, cb, direction = 'both') ->
    @queryRelationships kindOfRelationship, { action: 'DELETE', direction: direction }, cb

  Document::shortestPathTo = (doc, kindOfRelationship, cb) ->
    from = @
    to = doc
    from.getNode (errFrom, fromNode) -> to.getNode (errTo, toNode) ->
      return cb(new Error("Problem(s) getting from and/or to node")) if errFrom or errTo or not fromNode or not toNode
      levelDeepness = 15
      query = """
        START a = node(#{fromNode.id}), b = node(#{toNode.id}) 
        MATCH p = shortestPath( a-[*..#{levelDeepness}]->b )
        RETURN p;
      """
      from.queryGraph(query, cb)
