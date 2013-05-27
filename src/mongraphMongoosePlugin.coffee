_ = require('underscore')

module.exports = exports = mongraphMongoosePlugin = (schema, options = {}) ->

  schemaOptions = schema.options

  # skip if is set explizit to false
  return null if schemaOptions.graphability is false

  # set default option values for graphability
  schemaOptions.graphability            ?= {}
  schemaOptions.graphability.schema     ?= true
  schemaOptions.graphability.middleware ?= true
    
  # set default values, both hooks
  schemaOptions.graphability.middleware = {} if schemaOptions.graphability.middleware and typeof schemaOptions.graphability.middleware isnt 'object'
  schemaOptions.graphability.middleware.preRemove ?= true
  schemaOptions.graphability.middleware.preSave   ?= true
  schemaOptions.graphability.middleware.postInit  ?= true

  schemaOptions.graphability.relationships ?= {}
  schemaOptions.graphability.relationships.removeAllOutgoing ?= true
  schemaOptions.graphability.relationships.removeAllIncoming ?= true

  if schemaOptions.graphability.schema
    # node id of corresponding node
    schema.add
      _node_id: Number
      # add an empty object as placeholder for relationships, use is optional
      schema.add _relationships: {}

  # Extend middleware for graph use

  # if schemaOptions.graphability.middleware.postInit
  #   schema.post 'init', (doc) ->
  #     doc.indexInGraph()

  if schemaOptions.graphability.middleware.preRemove
    schema.pre 'remove', (errHandler, next) ->
      # skip remove node if no node id is set
      return next(null) unless @._node_id > 0
      # Remove also all relationships
      opts =
        includeRelationships: schemaOptions.graphability.relationships.removeAllOutgoing and schemaOptions.graphability.relationships.removeAllOutgoing
      @removeNode opts, next

  if schemaOptions.graphability.middleware.preSave
    schema.pre 'save', true, (next, done) ->
      # Attach/Save corresponding node
      doc = @
      next()
      doc.getNode { forceCreation: true }, (err, node) ->
        # if we have fields to store in node and they have to be inde
        dataForNode = doc.dataForNode()
        index = doc.dataForNode(index: true)
        if index?.length > 0
          doc.indexInGraph { node: node }, ->
            # TODO: implement exception handler
        if dataForNode
          # console.log dataForNode, node.id
          node.data = _.extend(node.data, dataForNode)
          node.save ->
            # TODO: implement exception handler
        done(err, node)

        
      

  


