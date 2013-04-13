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
    if options.relations.removeAllOutgoing && options.relations.removeAllOutgoing
      direction = 'both'
    else if options.relations.removeAllOutgoing
      direction = 'outgoing'
    else if options.relations.removeAllIncoming
      direction = 'incoming'
    doc.getNode (errGettingNode, node) ->
      return cb(errGettingNode) if errGettingNode
      doc.removeRelationships '*', { direction: direction } , (errRemoveRelationships) ->
        node.delete (errDeletingNode) ->
          # node will be delete, if removeAllOutgoing and removeAllIncoming is set to true
          return cb(errRemoveRelationships) if errRemoveRelationships
          return cb(errDeletingNode) if errDeletingNode
          # TODO: maybe pass a count of deleted relationships?!
          cb(null,null)

  schema.pre 'save', (next) ->
    # Attach node
    doc = @
    return next() if options.storeNodeID isnt true
    doc.findOrCreateCorrespondingNode (err, node) ->
      doc._node_id = node.id if node
      next()

  


