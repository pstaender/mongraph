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
  Node     = graphdb.Node

  # Check that we don't override existing functions
  if globalOptions.overrideProtoypeFunctions isnt true
    for functionName in [
      'applyGraphRelationships',
      'removeNode',
      'shortestPathTo',
      'allRelationshipsBetween',
      'incomingRelationshipsFrom',
      'outgoingRelationshipsTo',
      'removeRelationships',
      'removeRelationshipsBetween',
      'removeRelationshipsFrom',
      'removeRelationshipsTo',
      'outgoingRelationships',
      'incomingRelationships',
      'allRelationships',
      'queryRelationships',
      'queryGraph',
      'createRelationshipBetween',
      'createRelationshipFrom',
      'createRelationshipTo',
      'getNodeId',
      'getNode',
      'findCorrespondingNode',
      'dataForNode',
      'indexGraph'
    ]
      throw new Error("Will not override mongoose::Document.prototype.#{functionName}") unless typeof mongoose.Document::[functionName] is 'undefined'

  Document = mongoose.Document

  processtools.setMongoose(mongoose)

  # create a corresponding node, not for direct use
  Document::_createCorrespondingNode = (cb) ->
    doc = @
    id = doc._id.toString()
    # create a new one
    collectionName = doc.constructor.collection.name
    node = new Node {
      _id: id,
      _collection: collectionName
    }
    # use schema name for label
    node.label = processtools.getModelNameByCollectionName(collectionName)
    # autoindex on _id
    node.fields.indexes._id = true
    node.save (err, node) ->
      return cb(err, node) if err
      # adding legacacy index, too (collection/_id/)
      node.addIndex collectionName, '_id', id, (err) ->
        cb(err, node)


  #### Find or create the equivalent node to this Document 
  Document::getNode = (options, cb) ->
    {options, cb} = processtools.sortOptionsAndCallback(options,cb)
    return cb(Error('No graphability enabled'), null) unless @schema.get('graphability')
    doc = @

    # you can force a reloading of a node
    # so you can ensure to get the latest existing node directly from db
    options.forceReload ?= false

    # return attached node
    return cb(null, doc._node, options) if doc._node and options.forceReload isnt true

    collectionName = doc.constructor.collection.name
    id = processtools.getObjectIDAsString(doc)

    # Find equivalent node in graphdb    

    return cb(Error("Can't load a corresponding Node to an unpersisted document"), null) if doc.isNew and options.forceCreation isnt true

    #   # we can't find a corresponding node, if the doc is not persisted in the 
    #   cb(new Error("Can't return a 'corresponding' node of an unpersisted document"), null, options)
    Node::findByIndex collectionName, '_id', doc._id, (err, foundNode) ->
      if err
        cb(err, foundNode, options)
      else
        unless foundNode
          doc._createCorrespondingNode(cb)
        else
          cb(null, foundNode, options)

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
    @getNode (fromErr, from) ->
      doc.getNode (toErr, to) ->
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

  #### Loads in+outgoing relationships between to documents
  Document::allRelationshipsBetween = (to, typeOfRelationship, options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    from = @
    options.referenceDocumentID ?= from._id
    options.direction ?= 'both'
    to.getNode (err, endNode) ->
      return cb(Error('-> toDocument has no corresponding node',null)) unless endNode
      options.endNodeId = endNode.id
      from.queryRelationships(typeOfRelationship, options, cb)

  #### Loads incoming relationships between to documents
  Document::incomingRelationshipsFrom = (to, typeOfRelationship, options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    options.direction = 'incoming'
    @allRelationshipsBetween(to, typeOfRelationship, options, cb)

  #### Loads outgoin relationships between to documents
  Document::outgoingRelationshipsTo = (to, typeOfRelationship, options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    options.direction = 'outgoing'
    @allRelationshipsBetween(to, typeOfRelationship, options, cb)

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
      options.endNodeId = endNode.id
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
    this.getNode (err, node) ->
      if err then cb(err) else node.removeRelationships(cb)

  #### Delete node including all incoming and outgoing relationships
  Document::removeNode = (options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    doc = @
    doc.getNode (err, node) ->
      if err
        cb(err, node) if err
      else
        doc._node = null
        node.removeWithRelationships(cb)

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

  Document::dataForNode = (options = {}) ->
    self = @
    {index} = options
    index ?= false # returns fields for indexing if set to true; maybe as own method later
    paths = self.schema.paths
    flattenSeperator = '.' # make it configurable?!
    values  = {}
    indexes = []
    for path of paths
      definition = paths[path]
      if index
        indexes.push(path.split('.').join(flattenSeperator)) if definition.options?.graph is true and definition.options?.index is true
      else if definition.options?.graph is true
        values[path.split('.').join(flattenSeperator)] = self.get(path)
    if index
      indexes 
    else if Object.keys(values).length > 0
      values
    else
      null

  # ## Index Node
  # We taking the fields to index from mongoose schema (must set with graph: true)
  # TODO: replace with autoindex
  Document::indexGraph = (options, cb) ->
    {options,cb} = processtools.sortOptionsAndCallback(options,cb)
    doc = @
    node = options.node or doc._node
    index = doc.dataForNode(index: true)

    return cb(Error('No node given/attached'), null) unless node
    return cb(null, null) unless index.length > 0 # if we have nothing to index

    join = Join.create()
    collectionName = doc.constructor.collection.name

    for pathToIndex in index
      value = doc.get(pathToIndex)
      # index if have a value
      node.addIndex(collectionName, pathToIndex, value, join.add()) if typeof value isnt 'undefined'

    join.when ->
      cb(arguments[0], arguments[1]) if typeof cb is 'function'


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
    Node.neo4jrestful.query cypher, null, (errGraph, map) ->
      # Adding cypher query for better debugging
      options.debug = {} if options.debug is true
      options.debug?.cypher ?= []
      options.debug?.cypher?.push(cypher)
      options.loadDocuments ?= true # load documents from mongodb
      # TODO: would it be helpful to have also the `native` result?
      # TODO: processtools
      cb(errGraph, map)

  Document::_node = null

  

