require 'sketchup.rb'

plugin_menu = UI.menu("Plugins").add_submenu("EnvolvenCTE")

require "#{File.dirname(__FILE__)}/lib/src/Geometry"
require "#{File.dirname(__FILE__)}/lib/src/SketchUp"
require "#{File.dirname(__FILE__)}/lib/src/Utilities"

{
  'CaracteristicasEdificio' => "Definicion del caso y tipo de edificio",
  'Kglobal' => "K global",
  'qsolar' => "q solar"
}.each do |file_name, cmd_name|
  cmd = UI::Command.new(cmd_name)  { load(File.dirname(__FILE__)+"/lib/#{file_name}.rb") }
  plugin_menu.add_item(cmd)
end