_ = require("lodash")
$ = require("jquery")
Promise = require("bluebird")

$Cy = require("../../cy")
$Log = require("../../log")
utils = require("../../utils")

ngPrefixes = ['ng-', 'ng_', 'data-ng-', 'x-ng-']

$Cy.extend({
  ## these are private because only 'ng' should know
  ## about them.  we're attaching them regardless
  ## so they're reachable and can be monkey patched
  _findByNgBinding: (binding, options) ->
    selector = ".ng-binding"

    angular = @privateState("window").angular

    _.extend options, {verify: false, log: false}

    getEl = ($elements) ->
      filtered = $elements.filter (index, el) ->
        dataBinding = angular.element(el).data("$binding")

        if dataBinding
          bindingName = dataBinding.exp or dataBinding[0].exp or dataBinding
          return binding in bindingName

      ## if we have items return
      ## those filtered items
      if filtered.length
        return filtered

      ## else return null element
      return $(null)

    do resolveElements = =>
      @execute("get", selector, options).then ($elements) =>
        @verifyUpcomingAssertions(getEl($elements), options, {
          onRetry: resolveElements
          onFail: (err) ->
            err.displayMessage = "Could not find element for binding: '#{binding}'."
        })

  _findByNgAttr: (name, attr, el, options) ->
    selectors = []
    error = "Could not find element for #{name}: '#{el}'.  Searched "

    _.extend options, {verify: false, log: false}

    finds = _.map ngPrefixes, (prefix) =>
      selector = "[#{prefix}#{attr}'#{el}']"
      selectors.push(selector)

      do resolveElements = =>
        @execute("get", selector, options).then ($elements) =>
          @verifyUpcomingAssertions($elements, options, {
            onRetry: resolveElements
          })

    error += selectors.join(", ") + "."

    cancelAll = ->
      _.invokeMap(finds, "cancel")

    Promise
      .any(finds)
      .cancellable()
      .then (subject) ->
        cancelAll()
        return subject
      .catch Promise.CancellationError, (err) ->
        cancelAll()
        throw err
      .catch Promise.AggregateError, (err) =>
        utils.throwErr error
})

module.exports = (Cypress, Commands) ->
  Commands.addAll({
    ng: (type, selector, options = {}) ->
      ## what about requirejs / browserify?
      ## we need to intelligently check to see if we're using those
      ## and if angular is available through them.  throw a very specific
      ## error message here that's different depending on what module
      ## system you're using
      utils.throwErrByPath "ng.no_global" if not @privateState("window").angular

      _.defaults options, {log: true}

      if options.log
        options._log = $Log.command()

      switch type
        when "model"
          @_findByNgAttr("model", "model=", selector, options)
        when "repeater"
          @_findByNgAttr("repeater", "repeat*=", selector, options)
        when "binding"
          @_findByNgBinding(selector, options)
  })
