module.exports = exports = mongraphMongoosePlugin = (schema, options = {}) ->

  schema.add _node_id: Number

  options.storeNodeID ?= true
  options.relations ?= {}
  options.relations.removeAllOutgoing ?= true
  options.relations.removeAllIncoming ?= true

  # Extend middleware for graph use

  # Remove also all relationships
  # TODO: maybe better/best practice not to do and leave nodes?!? 
  schema.pre 'remove', (errHandler) ->
    doc = @
    doc.getNode (err, node) ->
      node.delete ->
        'node will be delete, if removeAllOutgoing and removeAllIncoming is set to true'
      , options.relations.removeAllOutgoing && options.relations.removeAllOutgoing

  schema.pre 'save', (next) ->
    # Attach node
    doc = @
    return next() if options.storeNodeID isnt true
    doc.findOrCreateEquivalentNode (err, node) ->
      doc._node_id = node.id if node
      next()

  


