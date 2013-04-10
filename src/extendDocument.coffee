processtools = require('./processtools')
_s = require('underscore.string')

module.exports = (mongodb, graphdb, globalOptions) ->

  Document = mongodb.Document

  node = graphdb.createNode()

  Document::_graphdb = {
    # handler for using for custom queries
    db: graphdb
  }

  _queryGraphDB = (cypher, options = {}, cb) ->
    options.loadDocuments ?= true
    # TODO: "mongodb.connection" doesn't work as expected
    # but options.mongodb native connection is mandatory
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
        processtools.loadDocumentsFromRelationshipArray options.mongodbConnection, data, cb
      else
        # prevent `undefined is not a function` if no cb is given
        cb(err, map) if typeof cb is 'function'

  ## Find equivalent node to document 
  Document::findEquivalentNode = (cb, doCreateIfNotExists = false) ->
    doc = @
    collectionName = doc.constructor.collection.name
    id = processtools.getObjectIDAsString(doc)
    # find equivalent node in graphdb
    # cache node existing?, not implemented
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

  # Find or create equivalent node to document, recommend to use this
  Document::findOrCreateEquivalentNode = (cb) -> @findEquivalentNode(cb, true)
  
  ## Shortcut -> findOrCreateEquivalentNode
  Document::getNode = (cb) ->
    @findOrCreateEquivalentNode(cb)

  ## Create a relationship from current document to a given document
  Document::createRelationshipTo = (doc, kindOfRelationship, attributes = {}, cb) ->
    # assign cb + attribute arguments
    if typeof attributes is 'function'
      cb = attributes
      attributes = {}
    # Is needed to load the records from mongodb
    # TODO: Currently we have to store these information redundant because
    # otherwise we would have to request each side for it's represantive node
    # seperately to get the information wich namespace/collection the mongodb records is stored
    # -->  would increase requests to neo4j heavily
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

  Document::createRelationshipFrom = (doc, kindOfRelationship, attributes = {}, cb) ->
    # alternate directions: doc -> this
    doc.createRelationshipTo(@, kindOfRelationship, attributes, cb)

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

  Document::queryGraph = (chypherQuery, options, cb) ->
    doc = @
    {options, cb} = processtools.sortOptionsAndCallback(options,cb)
    options.mongodbConnection = doc.db
    _queryGraphDB(chypherQuery, options, cb)

  
  Document::queryRelationships = (kindOfRelationship, options, cb) ->
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

  Document::allRelationships = (kindOfRelationship, cb) ->
    @queryRelationships(kindOfRelationship, { direction: 'both' }, cb)

  Document::incomingRelationships = (kindOfRelationship, cb) ->
    @queryRelationships(kindOfRelationship, { direction: 'incoming' }, cb)

  Document::outgoingRelationships = (kindOfRelationship, cb) ->
    @queryRelationships(kindOfRelationship, { direction: 'outgoing' }, cb)
  

  Document::removeRelationshipsTo = (doc, kindOfRelationship, cb, direction = 'outgoing') ->
    from = @
    doc.getNode (nodeErr, endNode) ->
      return cb(nodeErr, endNode) if nodeErr
      from.queryRelationships kindOfRelationship, { direction: direction, action: 'DELETE', endNode: endNode.id }, cb

  Document::removeRelationshipsFrom = (doc, kindOfRelationship, cb, direction = 'incoming') ->
    @removeRelationshipsTo(doc, kindOfRelationship, cb, direction)

  Document::removeRelationshipsBetween = (doc, kindOfRelationship, cb, direction = 'both') ->
    @removeRelationshipsTo(doc, kindOfRelationship, cb, direction)

  Document::removeRelationships = (kindOfRelationship, cb, direction = 'both') ->
    @queryRelationships kindOfRelationship, { action: 'DELETE', direction: direction }, cb


