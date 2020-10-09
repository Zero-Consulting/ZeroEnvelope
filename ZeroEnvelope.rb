require 'sketchup.rb' # defines the SketchupExtension class
require 'extensions.rb'

plugin_name = "EnvolvenCTE"

ext = SketchupExtension.new(plugin_name, "#{plugin_name}/Startup.rb")
ext.name = plugin_name
ext.description = "Computes some energy efficiency indicators of the thermal envelope according to CTE DB-HE 2019."
ext.version = "0.0.201006"
ext.creator = "Zero Consulting"
ext.copyright = "2020"

# 'true' automatically loads the extension the first time it is registered, e.g., after install
Sketchup.register_extension(ext, true)