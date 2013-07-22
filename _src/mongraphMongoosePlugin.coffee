_ = require('underscore')

module.exports = exports = mongraphMongoosePlugin = (schema, options = {}) ->

  # skip if is set explizit to false
  return null if schema.options.graphability is false

  schemaOptions =
    graphability:
      middleware:
        preRemove: true
        preSave: true
        postInit: true


  _.extend(schemaOptions.graphability, options.graphability) if options.graphability


  # Extend middleware for graph use


  if schemaOptions.graphability.middleware.preRemove
    schema.pre 'remove', (errHandler, next) ->
      @removeNode next

  if schemaOptions.graphability.middleware.preSave
    schema.pre 'save', true, (next, done) ->
      # Attach/Save corresponding node
      doc = @
      next()
      doc.getNode { forceCreation: true }, (err, node) ->
        # if we have fields to store in node and they have to be inde
        dataForNode = doc.dataForNode()
        index = doc.dataForNode(index: true)
        doc._node = node
        doc.indexGraph (err) ->
          # TODO: implement exception handler for index errors
          if dataForNode
            # console.log dataForNode, node.id
            node.data = _.extend(node.data, dataForNode)
            for path of dataForNode
              # delete a key/value if it has an undefined value
              delete(node.data[path]) if typeof dataForNode[path] is 'undefined'
            node.save(done)
          else
            done(err, node)



