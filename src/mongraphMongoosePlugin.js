var _ = require('underscore');

module.exports = exports = mongraphMongoosePlugin = function(schema, mongraphOptions) {

  var schemaOptions = schema.options || {};

  // skip if is set explizit to false
  if (!schemaOptions.graphability)
    return null;

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
        // if we have fields to store in node and they have to be inde
        dataForNode = doc.dataForNode();
        index = doc.dataForNode({ index: true });
        doc._node = node;
        doc.indexGraph(function(err) {
          // TODO: implement exception handler for index errors
          if (dataForNode) {
            node.data = _.extend(node.data, dataForNode);
            for (var path in dataForNode) {
              // delete a key/value if it has an undefined value
              if (typeof dataForNode[path] === 'undefined')
                delete(node.data[path]);
            }
            node.save(done);
          } else {
            done(err, node);
          }
        });
      });
  });

}