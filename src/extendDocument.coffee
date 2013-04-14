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

  processtools.setMongoose mongoose

  node = graphdb.createNode()

  #### Can be used to make native queries on neo4j
  # TODO: helpful / best practice? not sure... -> instead you should query directly via neo4j module
  Document::_graphdb = {
    # handler for using for custom queries
    db: graphdb
  }

  #### Private method to query neo4j directly
  #### options -> see Document::queryRelationships
  _queryGraphDB = (cypher, options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    options.loadDocuments ?= true
    options.countRelationships ?= false
    # TODO: type check
    graphdb.query cypher, (err, map) ->
      err.query = cypher if err
      # Adding cypher query for better debugging
      options.cypherQuery = cypher
      # TODO: would it be helpful to have also the direct result?
      # options.graphResult = map
      if options.loadDocuments and map?.length > 0
        # extract from result
        data = for result in map
          if options.processPart
            result[options.processPart]
          else
            # return first first property otherwise
            result[Object.keys(result)[0]]
        if processtools.constructorNameOf(data[0]) is 'Relationship'
          processtools.loadDocumentsFromRelationshipArray data, options, cb
        # TODO: distinguish between 'Path', 'Node' etc ...
        else
          processtools.loadDocumentsFromNodeArray data, options, cb
      else
        # prevent `undefined is not a function` if no cb is given
        cb(err, map, options) if typeof cb is 'function'

  #### Loads the equivalent node to this Document 
  Document::findCorrespondingNode = (options, cb) ->
    {options, cb} = processtools.sortOptionsAndCallback(options,cb)
    doc = @
    collectionName = doc.constructor.collection.name
    id = processtools.getObjectIDAsString(doc)

    # Difference between doCreateIfNotExists and forceCreation:
    #
    #   * doCreateIfNotExists -> persist the node if no corresponding node exists
    #   * forceCreation -> forces to create a node
    #
    # @forceCreation: this is needed because mongoose marks each document as
    # doc.new = true (which is checked to prevent accidently creating orphaned nodes).
    # As long it is 'init' doc.new stays true, but we need that to complete the 'pre' 'save' hook
    # (see -> mongraphMongoosePlugin) 

    options.doCreateIfNotExists ?= false
    options.forceCreation ?= false

    # Find equivalent node in graphdb
    
    # TODO: cache existing node
    
    _processNode = (node, doc, cb) ->
      # store document data also als in node -> untested and not recommend
      # known issue: neo4j doesn't store deeper levels of nested objects...
      if globalOptions.storeDocumentInGraphDatabase
        node.data = doc.toObject(globalOptions.storeDocumentInGraphDatabase)
        node.save()
      # store node_id on document
      doc._node_id = node.id
      cb(null, node)

    if doc.isNew is true and options.forceCreation isnt true
      cb(new Error("Can't return a 'corresponding' node of an unpersisted document"), null)
    else if doc._node_id
      graphdb.getNodeById doc._node_id, (errFound, node) ->
        if errFound
          cb(errFound, node)
        else
          _processNode(node,doc,cb)
    else if options.doCreateIfNotExists or options.forceCreation is true
      # create a new one
      node = graphdb.createNode( _id: id, collection: collectionName )
      node.save (errSave, node) ->
        if errSave
          cb(errSave, node)
        else
          # do index, but we don't use it anymore
          # TODO: remove maybe? maybe it can be used to query this way:
          # getIndexedNode '_id', doc._id ...
          node.index(collectionName, '_id', id)
          _processNode(node, doc, cb) 
    else
      cb(null,null)

  #### Finds or create equivalent Node to this Document
  Document::findOrCreateCorrespondingNode = (options, cb) ->
    {options, cb} = processtools.sortOptionsAndCallback(options,cb)
    @findCorrespondingNode(options, cb)
  
  # Recommend to use this method instead of `findOrCreateCorrespondingNode`
  # shortcutmethod -> findOrCreateCorrespondingNode
  Document::getNode = Document::findOrCreateCorrespondingNode


  #### Finds and returns id of corresponding Node
  # Faster, because it returns directly from document if stored (see -> mongraphMongoosePlugin)
  Document::getNodeId = (cb) ->
    if @_node_id
      cb(null, @_node_id)
    else
      @getNode cb

  #### Creates a relationship from this Document to a given document
  Document::createRelationshipTo = (doc, typeOfRelationship, attributes = {}, cb) ->
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
    @findOrCreateCorrespondingNode (fromErr, from) ->
      doc.findOrCreateCorrespondingNode (toErr, to) ->
        if from and to
          from.createRelationshipTo to, typeOfRelationship, attributes, cb
        else
          cb(fromErr or toErr, null) if typeof cb is 'function'
  
  #### Creates an incoming relationship from a given Documents to this Document
  Document::createRelationshipFrom = (doc, typeOfRelationship, attributes = {}, cb) ->
    # alternate directions: doc -> this
    doc.createRelationshipTo(@, typeOfRelationship, attributes, cb)

  #### Creates a bidrectional relationship between two Documents
  Document::createRelationshipBetween = (doc, typeOfRelationship, attributes = {}, cb) ->
    # both directions
    self = @
    found = []
    self.createRelationshipTo doc, typeOfRelationship, attributes, (err, first) ->
      return cb(err) if err
      found.push(first)
      doc.createRelationshipTo self, typeOfRelationship, attributes, (err, second) ->
        return cb(err) if err
        found.push(second)
        cb(err, found) if typeof cb is 'function'

  #### Query the graphdb with cypher, current Document is not relevant for the query 
  Document::queryGraph = (chypherQuery, options, cb) ->
    {options, cb} = processtools.sortOptionsAndCallback(options,cb)
    doc = @
    _queryGraphDB(chypherQuery, options, cb)

  #### Allows extended querying to the graphdb and loads found Documents
  #### (is used by many methods for loading incoming + outgoing relationships) 
  # @param typeOfRelationship = '*' (any relationship you can query with cypher, e.g. KNOW, LOVE|KNOW ...)
  # @param options = {}
  # (first value is default)
  # * direction (both|incoming|outgoing)
  # * action: (RETURN|DELETE|...) (all other actions wich can be used in cypher)
  # * processPart: (relationship|path|...) (depends on the result you expect from our query)
  # * loadDocuments: (true|false)
  # * endNode: '' (can be a node object or a nodeID)
  Document::queryRelationships = (typeOfRelationship, options, cb) ->
    _s = require('underscore.string')
    # options can be a cypher query as string
    options = { query: options } if typeof options is 'string'
    {options, cb} = processtools.sortOptionsAndCallback(options,cb)
    # build query from options
    typeOfRelationship ?= '*'
    typeOfRelationship = if /^[*:]{1}$/.test(typeOfRelationship) or not typeOfRelationship then '' else ':'+typeOfRelationship
    options.direction ?= 'both'
    options.action ?= "RETURN"
    options.processPart ?= "relation"    
    # endNode can be string or node object
    options.endNode ?= ""
    options.endNode = endNode.id if typeof endNode is 'object'    
    doc = @
    id = processtools.getObjectIDAsString(doc)
    @getNode (nodeErr, fromNode) ->
      # if no node is found
      return cb(nodeErr, null) if nodeErr
      cypher = """
                START a = node(%(id)s)%(endNode)s
                MATCH (a)%(incoming)s[relation%(relation)s]%(outgoing)s(b)
                %(action)s %(processPart)s;
               """
      cypher = _s.sprintf cypher,
        id:             fromNode.id
        incoming:       if options.direction is 'incoming' then '<-' else '-'
        outgoing:       if options.direction is 'outgoing' then '->' else '-'
        relation:       typeOfRelationship
        action:         options.action.toUpperCase()
        processPart:    options.processPart
        endNode:        if options.endNode then ", b = node(#{options.endNode})" else ''
      options.startNode ?= fromNode.id # for logging
      if options.query
        # take query from options and discard build query
        cypher = query
      if options.dontExecute
        cb({ message: "`dontExecute` options is set", query: cypher, options: options }, null)
      else
        _queryGraphDB(cypher, options, cb)

  #### Loads incoming and outgoing relationships
  Document::allRelationships = (typeOfRelationship, options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    options.direction = 'both'
    @queryRelationships(typeOfRelationship, options, cb)

  #### Loads incoming relationships
  Document::incomingRelationships = (typeOfRelationship, options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    options.direction = 'incoming'
    @queryRelationships(typeOfRelationship, options, cb)

  #### Loads outgoing relationships
  Document::outgoingRelationships = (typeOfRelationship, options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    options.direction = 'outgoing'
    @queryRelationships(typeOfRelationship, options, cb)
  
  #### Remove outgoing relationships to a specific Document
  Document::removeRelationshipsTo = (doc, typeOfRelationship, options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    options.direction ?= 'outgoing'
    options.action = 'DELETE'
    from = @
    doc.getNode (nodeErr, endNode) ->
      return cb(nodeErr, endNode) if nodeErr
      options.endNode = endNode.id
      from.queryRelationships typeOfRelationship, options, cb

  #### Removes incoming relationships to a specific Document
  Document::removeRelationshipsFrom = (doc, typeOfRelationship, options, cb) ->
    to = @
    doc.removeRelationshipsTo to, typeOfRelationship, options, cb

  #### Removes incoming ad outgoing relationships between two Documents
  Document::removeRelationshipsBetween = (doc, typeOfRelationship, options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    options.direction = 'both'
    @removeRelationshipsTo(doc, typeOfRelationship, options, cb)

  #### Removes incoming and outgoing relationships to all Documents (useful bevor deleting a node/document)
  Document::removeRelationships = (typeOfRelationship, options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    options.direction = 'both'
    options.action = 'DELETE'
    @queryRelationships typeOfRelationship, options, cb

  #### Delete node including all incoming and outgoing relationships
  Document::removeNode = (options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    # we don't distinguish between incoming and outgoing relationships here
    # would it make sense?! not sure...
    options.includeRelationships ?= true
    doc = @
    doc.getNode (err, node) ->
      # if we have an error or no node found (as expected)
      if err or typeof node isnt 'object'
        return cb(err or new Error('No corresponding node found to document #'+doc._id), node) if typeof cb is 'function'
      else
        cypher = """
          START n = node(#{node.id})
          MATCH n-[r]-()
          DELETE n#{if options.includeRelationships then ', r' else ''}
        """
        _queryGraphDB(cypher, options, cb)

  #### Returns the shortest path between this and another document
  Document::shortestPathTo = (doc, typeOfRelationship, options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
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
      from.queryGraph(query, options, cb)

  # Document::removeWithNode = (options, cb) ->
  #   {options,cb} = processtools.sortOptionsAndCallback(options,cb)
  #   doc = @
  #   options.removeAllOutgoing ?= true
  #   options.removeAllIncoming ?= true
  #   if options.removeAllOutgoing && options.removeAllOutgoing
  #     direction = 'both'
  #   else if options.removeAllOutgoing
  #     direction = 'outgoing'
  #   else if options.removeAllIncoming
  #     direction = 'incoming'
  #   # console.log(doc._id, doc.name)
  #   doc.getNode (errGettingNode, node) ->
  #     # console.log 'remove', doc.name, direction
  #     if direction is 'both'
  #       doc.removeNode (err) ->
  #         doc.remove(cb)
  #     else
  #       doc.removeRelationships '*', { direction: direction } , (errRemoveRelationships) ->
  #         node.delete (errDeletingNode) ->
  #           # node will be delete, if removeAllOutgoing and removeAllIncoming is set to true
  #           # TODO: maybe pass a count of deleted relationships?!
  #           # Collect all errors
  #           errorMessage = []
  #           for error in [ errGettingNode or null, errRemoveRelationships or null, errDeletingNode or null ]
  #             message = error?.message or error
  #             errorMessage.push(message) if message
  #           errorMessage = if errorMessage.length > 0 then errorMessage.join(', ') else null
  #           if typeof cb is 'function'
  #             cb(errorMessage,null) if errorMessage
  #             doc.remove(cb)
