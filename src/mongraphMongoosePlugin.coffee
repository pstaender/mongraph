module.exports = exports = mongraphMongoosePlugin = (schema, options = {}) ->

  schema.add {
    # node id of corresponding node
    _node_id: Number,
  }

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

  schema.pre 'save', true, (next, done) ->
    # Attach node
    doc = @
    next()
    doc.getNode { forceCreation: true }, done
      

  


