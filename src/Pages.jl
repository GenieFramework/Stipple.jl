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

@reactive struct EmptyModel <: ReactiveModel
end

mutable struct Page{M<:ReactiveModel}
  route::Route
  view::Genie.Renderers.FilePath
  model::Type{M}
  layout::Genie.Renderers.FilePath
end

const _pages = Page[]
pages() = _pages

function Page(  route::Union{Route,String};
                view::Union{Genie.Renderers.FilePath,String},
                model::Union{M,Function} = Stipple.init(EmptyModel),
                layout::Union{Genie.Renderers.FilePath,String,Nothing} = nothing,
                context::Module = @__MODULE__
              ) where {M<:ReactiveModel}
  route = isa(route, String) ? Route(; method = GET, path = route) : route
  view = isa(view, String) ? filepath(view) : view
  layout = isa(layout, String) ? filepath(layout) : layout

  route.action = () -> html(view; layout, context, model = (isa(model,Function) ? Base.invokelatest(model) : model))

  Router.route(route)

  push!(_pages, Page(route, view, typeof((isa(model,Function) ? Base.invokelatest(model) : model)), layout))
end

end