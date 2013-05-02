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

  options.relationships ?= {}
  options.relationships.removeAllOutgoing ?= true
  options.relationships.removeAllIncoming ?= true

  if schemaOptions.graphability.schema
    # node id of corresponding node
    schema.add
      _node_id: Number
      # add an empty object as placeholder for relationships, use is optional
      schema.add _relationships: {}

  # Extend middleware for graph use

  if schemaOptions.graphability.middleware.preRemove
    schema.pre 'remove', (errHandler, next) ->
      # skip remove node if no node id is set
      return next(null) unless @._node_id > 0
      # Remove also all relationships
      opts =
        includeRelationships: options.relationships.removeAllOutgoing and options.relationships.removeAllOutgoing
      @removeNode opts, next

  if schemaOptions.graphability.middleware.preSave
    schema.pre 'save', true, (next, done) ->
      # Attach/Save corresponding node
      doc = @
      next()
      doc.getNode { forceCreation: true }, done
      

  


