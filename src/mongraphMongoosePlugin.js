var _ = require('underscore');

module.exports = exports = mongraphMongoosePlugin = function(schema, mongraphOptions) {

  var schemaOptions = schema.options || {};

  // skip if is set explizit to false
  if (schemaOptions.graphability === false)
    return null;
  else
    // apply default values
    schemaOptions.graphability = _.extend(mongraphOptions.graphability, schemaOptions.graphability || {});

  // Extend middleware for graph use
  if (schemaOptions.graphability.middleware.preRemove)
    schema.pre('remove', function(errHandler, next) {
      this.removeNode(next);
    });

  if (schemaOptions.graphability.middleware.preSave)
    schema.pre('save', true, function(next, done) {
      // Attach/Save corresponding node
      doc = this;
      next();
      doc.getNode({ forceCreation: true }, function(err, node) {
        if (mongraphOptions.cacheNodeInDocument)
          doc._cachedNode_ = node;
        done();
      });
  });

}