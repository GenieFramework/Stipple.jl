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

mutable struct Page
  route::Route
  view::Union{Genie.Renderers.FilePath,<:AbstractString}
  model
  layout::Union{Genie.Renderers.FilePath,<:AbstractString,Nothing}
  context::Module
end

const _pages = Page[]
pages() = _pages

function Page(  route::Union{Route,String};
                view::Union{Genie.Renderers.FilePath,<:AbstractString,ParsedHTMLString,Vector{T}},
                model::Union{M,Function,Nothing,Expr} = Stipple.init(EmptyModel),
                layout::Union{Genie.Renderers.FilePath,<:AbstractString,ParsedHTMLString,Nothing} = nothing,
                context::Module = @__MODULE__,
                kwargs...
              ) where {M<:ReactiveModel,T<:AbstractString}

  view =  if isa(view, ParsedHTMLString) || isa(view, Vector{T})
            string(view)
          elseif isa(view, AbstractString)
            isfile(view) ? filepath(view) : view
          else
            view
          end

  isa(model, Expr) && (model = Core.eval(context, model))
  route = isa(route, String) ? Route(; method = GET, path = route) : route
  layout = isa(layout, String) && isfile(layout) ? filepath(layout) :
            isa(layout, ParsedHTMLString) || isa(layout, String) ? string(layout) :
              layout

  route.action = () -> html(view; layout, context, model = (isa(model,Function) ? Base.invokelatest(model) : model), kwargs...)

  page = Page(route, view, typeof((isa(model,Function) || isa(model,DataType) ? Base.invokelatest(model) : model)), layout, context)

  if isempty(_pages)
    push!(_pages, page)
  else
    for i in eachindex(_pages)
      if _pages[i].route.path == route.path && _pages[i].route.method == route.method
        Router.delete!(Router.routename(_pages[i].route))
        _pages[i] = page
      else
        push!(_pages, page)
      end
    end
  end

  Router.route(route)

  page
end

function delete!(page::Page)
  deleteat!(_pages, findall(p -> p == page, _pages))
end

function remove_pages()
  empty!(_pages)
end

end