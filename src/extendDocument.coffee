# ### Extend Document
#
# This models extends the mongodb/mongoose Document with:
# * allows creating, deleting and querying all kind of incoming and outgoing relationships
# * native queries on neo4j with option to load Documents by default
# * connects each Document with corresponding Node in neo4j
#
# TODO: check that we always get Documents as mongoose models

_s = require('underscore.string')
processtools = require('./processtools')
Join = require('join')

module.exports = (globalOptions) ->

  mongoose = globalOptions.mongoose
  graphdb  = globalOptions.neo4j

  # Check that we don't override existing functions
  if globalOptions.overrideProtypeFunctions isnt true
    for functionName in [ 'applyGraphRelationships', 'removeNode', 'shortestPathTo', 'removeRelationships', 'removeRelationshipsBetween', 'removeRelationshipsFrom', 'removeRelationshipsTo', 'outgoingRelationships', 'incomingRelationships', 'allRelationships', 'queryRelationships', 'queryGraph', 'createRelationshipBetween', 'createRelationshipFrom', 'createRelationshipTo', 'getNodeId', 'findOrCreateCorrespondingNode', 'findCorrespondingNode' ]
      throw new Error("Will not override mongoose::Document.prototype.#{functionName}") unless typeof mongoose.Document::[functionName] is 'undefined'

  Document = mongoose.Document

  processtools.setMongoose mongoose

  node = graphdb.createNode()

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
    # REMOVED: options can be a cypher query as string
    # options = { query: options } if typeof options is 'string'
    {typeOfRelationship,options, cb} = processtools.sortTypeOfRelationshipAndOptionsAndCallback(typeOfRelationship,options,cb)
    # build query from options
    typeOfRelationship ?= '*'
    typeOfRelationship = if /^[*:]{1}$/.test(typeOfRelationship) or not typeOfRelationship then '' else ':'+typeOfRelationship
    options.direction ?= 'both'
    options.action ?= 'RETURN'
    options.processPart ?= 'r'   
    options.referenceDocumentID ?= @_id 
    # endNode can be string or node object
    options.endNode ?= ''
    options.endNode = endNode.id if typeof endNode is 'object'
    options.debug = {} if options.debug is true
    doc = @
    id = processtools.getObjectIDAsString(doc)
    @getNode (nodeErr, fromNode) ->
      # if no node is found
      return cb(nodeErr, null, options) if nodeErr

      

      cypher = """
                START a = node(%(id)s)%(endNode)s
                MATCH (a)%(incoming)s[r%(relation)s]%(outgoing)s(b)
                %(whereRelationship)s
                %(action)s %(processPart)s;
               """
      


      cypher = _s.sprintf cypher,
        id:                 fromNode.id
        incoming:           if options.direction is 'incoming' then '<-' else '-'
        outgoing:           if options.direction is 'outgoing' then '->' else '-'
        relation:           typeOfRelationship
        action:             options.action.toUpperCase()
        processPart:        options.processPart
        whereRelationship:  if options.where?.relationship then "WHERE #{options.where.relationship}" else ''
        endNode:            if options.endNode then ", b = node(#{options.endNode})" else ''
      options.startNode     ?= fromNode.id # for logging
      

      # take query from options and discard build query
      cypher = options.cypher if options.cypher
      options.debug?.cypher ?= []
      options.debug?.cypher?.push(cypher)
      if options.dontExecute
        cb(Error("`options.dontExecute` is set to true..."), null, options)
      else
        _queryGraphDB(cypher, options, cb)


  #### Loads the equivalent node to this Document 
  Document::findCorrespondingNode = (options, cb) ->
    {options, cb} = processtools.sortOptionsAndCallback(options,cb)
    doc = @

    # you can force a reloading of a node
    # so you can ensure to get the latest existing node directly from db
    options.forceReload ?= false

    return cb(null, doc._cached_node, options) if globalOptions.cacheAttachedNodes and doc._cached_node and options.forceReload isnt true

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
      doc._cached_node = node if globalOptions.cacheAttachedNodes
      cb(null, node, options)

    if doc.isNew is true and options.forceCreation isnt true
      cb(new Error("Can't return a 'corresponding' node of an unpersisted document"), null, options)
    else if doc._node_id
      graphdb.getNodeById doc._node_id, (errFound, node) ->
        if errFound
          cb(errFound, node, options)
        else
          _processNode(node,doc,cb)
    else if options.doCreateIfNotExists or options.forceCreation is true
      # create a new one
      node = graphdb.createNode( _id: id, collection: collectionName )
      node.save (errSave, node) ->
        if errSave
          cb(errSave, node, options)
        else
          # do index for better queries outside mongraph
          # e.g. people/_id/5178fb1b48c7a4ae24000001
          node.index(collectionName, '_id', id)
          _processNode(node, doc, cb) 
    else
      cb(null, null, options)

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
    {attributes,cb} = processtools.sortAttributesAndCallback(attributes,cb)
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
          from.createRelationshipTo to, typeOfRelationship, attributes, (err, result) ->
            return cb(err, result) if err
            processtools.populateResultWithDocuments result, {}, cb
        else
          cb(fromErr or toErr, null) if typeof cb is 'function'
  
  #### Creates an incoming relationship from a given Documents to this Document
  Document::createRelationshipFrom = (doc, typeOfRelationship, attributes = {}, cb) ->
    {attributes,cb} = processtools.sortAttributesAndCallback(attributes,cb)
    # alternate directions: doc -> this
    doc.createRelationshipTo(@, typeOfRelationship, attributes, cb)

  #### Creates a bidrectional relationship between two Documents
  Document::createRelationshipBetween = (doc, typeOfRelationship, attributes = {}, cb) ->
    # both directions
    {attributes,cb} = processtools.sortAttributesAndCallback(attributes,cb)
    from = @
    to = doc
    from.createRelationshipTo to, typeOfRelationship, (err1) -> to.createRelationshipTo from, typeOfRelationship, (err2) ->
      cb(err1 || err2, null)

  #### Query the graphdb with cypher, current Document is not relevant for the query 
  Document::queryGraph = (chypherQuery, options, cb) ->
    {options, cb} = processtools.sortOptionsAndCallback(options,cb)
    doc = @
    _queryGraphDB(chypherQuery, options, cb)

  #### Loads incoming and outgoing relationships
  Document::allRelationships = (typeOfRelationship, options, cb) ->
    {typeOfRelationship, options, cb} = processtools.sortTypeOfRelationshipAndOptionsAndCallback(typeOfRelationship, options, cb)
    options.direction = 'both'
    options.referenceDocumentID = @_id
    @queryRelationships(typeOfRelationship, options, cb)

  #### Loads incoming relationships
  Document::incomingRelationships = (typeOfRelationship, options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    options.direction = 'incoming'
    options.referenceDocumentID = @_id
    @queryRelationships(typeOfRelationship, options, cb)

  #### Loads outgoing relationships
  Document::outgoingRelationships = (typeOfRelationship, options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    options.direction = 'outgoing'
    options.referenceDocumentID = @_id
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
        return cb(err || new Error('No corresponding node found to document #'+doc._id), node) if typeof cb is 'function'
      else
        cypher = """
          START n = node(#{node.id})
          MATCH n-[r?]-()
          DELETE n#{if options.includeRelationships then ', r' else ''}
        """
        _queryGraphDB(cypher, options, cb)

  #### Returns the shortest path between this and another document
  Document::shortestPathTo = (doc, typeOfRelationship = '', options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    from = @
    to = doc
    from.getNode (errFrom, fromNode) -> to.getNode (errTo, toNode) ->
      return cb(new Error("Problem(s) getting from and/or to node")) if errFrom or errTo or not fromNode or not toNode
      levelDeepness = 15
      query = """
        START a = node(#{fromNode.id}), b = node(#{toNode.id}) 
        MATCH path = shortestPath( a-[#{if typeOfRelationship then ':'+typeOfRelationship else ''}*..#{levelDeepness}]->b )
        RETURN path;
      """
      options.processPart = 'path'
      from.queryGraph(query, options, cb)

  # TODO: refactor -> split into more methods

  Document::applyGraphRelationships = (options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    # relationships will be stored permanently on this document
    # not for productive usage
    # -> it's deactivated by default, because I'm not sure that it'a good idea
    # to store informations redundant (CAP/syncing)
    options.doPersist ?= false
    sortedRelationships = {}
    typeOfRelationship = '*' # TODO: make optional
    doc = @
    # Schema
    # 
    # typeOfRelationship: [
    #   from:
    #     collection: String
    #     _id: ObjectId
    #     data: {}
    #   to:
    #     collection: String
    #     _id: ObjectId
    #     data: {}
    # ]

    _finally = (err, result, options) ->
      doc._relationships = sortedRelationships # attach to current document
      cb(err, doc._relationships, options) if typeof cb is 'function'

    doc.getNode options, (err, node, options) ->
      return _finally(err, node, options) if err
      doc.allRelationships typeOfRelationship, options, (err, relationships, options) ->
        return _finally(err, relationships, options) if err
        if relationships?.length > 0
          # add relationships to object, sorted by type (see above for schema)          
          for relation in relationships
            if relation._data?.type
              data = {}
              for part in [ 'from', 'to' ]
                {collectionName,_id} = processtools.extractCollectionAndId(relation.data["_#{part}"])
                data[part] =
                  collection: collectionName
                  _id: processtools.ObjectId(_id)
              sortedRelationships[relation._data.type] ?= []
              sortedRelationships[relation._data.type].push(data)
        doc._relationships = sortedRelationships
        if typeOfRelationship is '*'
          conditions = { _relationships: sortedRelationships }
          # update all -> slower
          if options.doPersist
            options?.debug?.where.push(conditions)
            doc.update conditions, (err, result) -> _finally(err,result,options)
          else
            _finally(err,null,options)
        else
          key = '_relationships.'+typeOfRelationship
          update = {}
          update[key] = sortedRelationships[typeOfRelationship]
          conditions = update
          options?.debug?.where.push(conditions)
          if sortedRelationships[typeOfRelationship]?
            doc.update conditions, (err, result) -> _finally(err,result,options)
          else
            # remove/unset attribute
            update[key] = 1 # used to get mongodb query like -> { $unset: { key: 1 } }
            conditions = { $unset: update }
            
            if options.doPersist
              options?.debug?.where.push(conditions)
              doc.update conditions, (err, result) -> _finally(err,result,options)
            else
              _finally(err,null,options)


  #### Private method to query neo4j directly
  #### options -> see Document::queryRelationships
  _queryGraphDB = (cypher, options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    # TODO: type check
    # try to "guess" process part from last statement
    # TODO: nice or bad feature?! ... maybe too much magic 
    if not options.processPart? and cypher.trim().match(/(RETURN|DELETE)\s+([a-zA-Z]+?)[;]*$/)?[2]
      options.processPart = cypher.trim().match(/(RETURN|DELETE)\s+([a-zA-Z]+?)[;]*$/)[2]
    graphdb.query cypher, null, (errGraph, map) ->
      # Adding cypher query for better debugging
      options.debug = {} if options.debug is true
      options.debug?.cypher ?= []
      options.debug?.cypher?.push(cypher)
      options.loadDocuments ?= true # load documents from mongodb
      # TODO: would it be helpful to have also the `native` result?
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
          processtools.populateResultWithDocuments data, options, cb
        # TODO: distinguish between 'Path', 'Node' etc ...
        else
          processtools.populateResultWithDocuments data, options, cb
      else
        # prevent `undefined is not a function` if no cb is given
        cb(errGraph, map || null, options) if typeof cb is 'function'

  #### Cache node
  if globalOptions.cacheAttachedNodes
    Document::_cached_node = null
  

