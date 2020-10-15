require 'sketchup.rb' # defines the SketchupExtension class
require 'extensions.rb'

plugin_name = "ZeroEnvelope"

ext = SketchupExtension.new(plugin_name, "#{plugin_name.downcase}/Startup.rb")
ext.name = plugin_name
ext.description = "Computes some energy efficiency indicators of the thermal envelope according to CTE DB-HE."
ext.version = "0.1.0"
ext.creator = "Zero Consulting"
ext.copyright = "2020"

# 'true' automatically loads the extension the first time it is registered, e.g., after install
Sketchup.register_extension(ext, true)