processtools = require('./processtools')

module.exports = exports = mongraphMongoosePlugin = (schema, options = {}) ->

  options.relationships ?= {}
  options.relationships.removeAllOutgoing  ?= true
  options.relationships.removeAllIncoming  ?= true

  # node id of corresponding node
  schema.add
    _node_id: Number
    schema.add _relationships: {} # add an empty object as placeholder for relationships, use is optional

  # Extend middleware for graph use

  # Remove also all relationships
  # TODO: maybe better/best practice not to do and leave nodes?!? 
  schema.pre 'remove', (errHandler, cb) ->
    opts =
      includeRelationships: options.relationships.removeAllOutgoing and options.relationships.removeAllOutgoing
    @removeNode opts, cb

  schema.pre 'save', true, (next, done) ->
    # Attach node
    doc = @
    next()
    doc.getNode { forceCreation: true }, done
      

  


