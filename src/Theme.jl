"""
Utility functions for working with themes.
"""
module Theme

using Genie
using Stipple

import Base.RefValue

"""
A dictionary of themes. Each theme is a string that represents a CSS class.
Add your own themes here.
"""
const THEMES = RefValue(Dict{Symbol, String}(
	:default => "theme-default-light",
  :dark => "theme-default-dark",
))


"""
The current theme.
"""
const CURRENT_THEME = RefValue(:default)


"""
Stores the index of the theme in Stipple.Layout.THEMES[]
"""
const THEME_INDEX = RefValue(0) #TODO: this will need to be refactored to manage themes in a dict by name -- but it will be breaking


"""
Get all the themes.
"""
function get_themes()
  return THEMES[]
end


"""
Get the current theme.
"""
function set_theme(theme::Symbol) :: Bool
	if haskey(get_themes(), theme)
		CURRENT_THEME[] = theme
    return true
  end

  return false
end


"""
Get the current theme.
"""
function get_theme()
  return CURRENT_THEME[]
end


"""
Register a new theme.
"""
function register_theme(name::Symbol, theme::String)
  get_themes()[name] = theme
end


"""
Unregister a theme.
"""
function unregister_theme(name::Symbol)
  theme_exists(name) && delete!(get_themes(), name)
end


"""
Check if a theme exists.
"""
function theme_exists(theme::Symbol)
  return haskey(get_themes(), theme)
end


"""
Get the URL or path to the theme's stylesheet.
"""
function to_path(theme::Symbol = CURRENT_THEME[]) :: String
  theme_path = theme_exists(theme) ? get_themes()[theme] : return ""

  return if startswith(theme_path, "http://") || startswith(theme_path, "https://") # external URL
    theme_path
  elseif startswith(theme_path, "/") # relative URL
    theme_path
  else # asset path
    Genie.Assets.asset_path(Stipple.assets_config, :css, path=Stipple.THEMES_FOLDER, file=theme_path)
  end
end


"""
Get the current theme as a stylesheet to be loaded into Stipple.Layout.THEMES[]
"""
function to_asset(theme::Symbol = CURRENT_THEME[]) :: Function
  theme_path = theme_exists(theme) ? get_themes()[theme] : return () -> ""

  return if startswith(theme_path, "http://") || startswith(theme_path, "https://") || startswith(theme_path, "/")
    () -> stylesheet(theme_path)
  else
    () -> stylesheet(Genie.Assets.asset_path(Stipple.assets_config, :css, path=Stipple.THEMES_FOLDER, file=theme_path))
  end
end

end
