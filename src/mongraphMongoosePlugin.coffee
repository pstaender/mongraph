module.exports = exports = mongraphMongoosePlugin = (schema, options = {}) ->

  schema.add {
    # node id of corresponding node
    _node_id: Number,
  }

  options.storeNodeID ?= true
  options.relations ?= {}
  options.relations.removeAllOutgoing ?= true
  options.relations.removeAllIncoming ?= true

  # Extend middleware for graph use

  # Remove also all relationships
  # TODO: maybe better/best practice not to do and leave nodes?!? 
  schema.pre 'remove', (errHandler, cb) ->
    opts =
      includeRelationships: options.relations.removeAllOutgoing and options.relations.removeAllOutgoing
    @removeNode opts, cb

  schema.pre 'save', (next) ->
    # Attach node
    doc = @
    return next() if options.storeNodeID isnt true
    doc.getNode { forceCreation: true }, (err, node) ->
      # Is made in findOrCreateCorrespondingNode -> doc._node_id = node.id if node
      next()

  


