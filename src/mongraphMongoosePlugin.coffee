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

  if schemaOptions.graphability.middleware.preRemove
    schema.pre 'remove', (errHandler, next) ->
      @removeWithGraph next

  if schemaOptions.graphability.middleware.preSave
    schema.pre 'save', true, (next, done) ->
      # Attach/Save corresponding node
      doc = @
      next()
      doc.getNode { forceCreation: true }, done
      

  


