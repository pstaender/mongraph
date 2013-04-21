_ = require('underscore')
processtools = require('./processtools')

# same issues as `extendRelationship`
Path = 

  toObject: ->
    { nodes: @_nodes || null, relationships: @_relationships, data: @_data?.data, id: @id, getParent: -> @ }

exports.extend = (pathObject) ->

  return pathObject unless typeof pathObject is 'object'

  _.extend(pathObject, Path)
  
