"""
Utility module to help define pages (dashboards) as bundles of route, view and model.
"""
module Pages

using Genie.Router
import Genie.Router: Route

using Genie.Renderers
using Genie.Renderers.Html
using Stipple

export Page
export pages

@reactive mutable struct EmptyModel <: ReactiveModel
end

mutable struct Page{M<:ReactiveModel}
  route::Route
  view::Union{Genie.Renderers.FilePath,<:AbstractString}
  model::Type{M}
  layout::Union{Genie.Renderers.FilePath,<:AbstractString,Nothing}
end

const _pages = Page[]
pages() = _pages

function Page(  route::Union{Route,String};
                view::Union{Genie.Renderers.FilePath,<:AbstractString,ParsedHTMLString},
                model::Union{M,Function,Expr,Nothing} = Stipple.init(EmptyModel),
                layout::Union{Genie.Renderers.FilePath,<:AbstractString,ParsedHTMLString,Nothing} = nothing,
                context::Module = @__MODULE__,
                kwargs...
              ) where {M<:ReactiveModel}
  isa(model, Expr) && (model = Core.eval(context, model))
  route = isa(route, String) ? Route(; method = GET, path = route) : route
  view = isa(view, String) && isfile(view) ? filepath(view) :
          isa(view, ParsedHTMLString) ? string(view) :
            view
  layout = isa(layout, String) && isfile(layout) ? filepath(layout) :
            isa(layout, ParsedHTMLString) || isa(layout, String) ? string(layout) :
              layout

  route.action = () -> html(view; layout, context, model = (isa(model,Function) ? Base.invokelatest(model) : model), kwargs...)

  Router.route(route)

  push!(_pages, Page(route, view, typeof((isa(model,Function) ? Base.invokelatest(model) : model)), layout))
end

end