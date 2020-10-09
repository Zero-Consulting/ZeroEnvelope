
module OpenStudio
  
  os_model = Plugin.model_manager.model_interface.openstudio_model
  su_model = Sketchup.active_model
  
  lZ = os_model.getClimateZones
  
  prompts, defaults, list = [], [], []
  
  zonaClimatica = lZ.getClimateZone('CTE', 0).value
  
  prompts << "Zona Climatica"
  choices = []
  choices << "A3"
  choices << "A4"
  choices << "B3"
  choices << "B4"
  choices << "C1"
  choices << "C2"
  choices << "C3"
  choices << "C4"
  choices << "D1"
  choices << "D2"
  choices << "D3"
  choices << "E1"
  choices << "alpha1"
  choices << "alpha2"
  choices << "alpha3"
  choices << "alpha4"
  choices << "A1c"
  choices << "A2c"
  choices << "A3c"
  choices << "A4c"
  choices << "B1c"
  choices << "B2c"
  choices << "B3c"
  choices << "B4c"
  choices << "C1c"
  choices << "C2c"
  choices << "C3c"
  choices << "C4c"
  choices << "D1c"
  choices << "D2c"
  choices << "D3c"
  choices << "E1c"
  list << choices.join("|")
  defaults << (zonaClimatica.empty? ? "D3" : zonaClimatica )
  
  nuevoOExistente, residencialOTerciario = "Edificio NUEVO", nil
  while true do
    standards_building_type = os_model.building.get.standardsBuildingType()
    break if standards_building_type.empty?
    
    aux = standards_building_type.get.split("-").map do |x| x.strip() end
    break unless aux.length.eql?(3)
    
    nuevoOExistente = aux[0]
    residencialOTerciario = aux[1..-1].join("-")
    break
  end
  
  prompts << "Residencial o Terciario"
  choices = []
  choices << "Residencial-Unifamiliar"
  choices << "Residencial-Bloque de Viviendas"
  choices << "Residencial-Vivienda Individual"
  choices << "Terciario-Edificio completo"
  choices << "Terciario-Local"
  list << choices.join("|")
  defaults << (residencialOTerciario || choices.first)

  permeabilidadHuecos = lZ.getClimateZone('PermeabilidadHuecos', 0).value

  prompts << "Permeabilidad huecos (m3/h-m2-100Pa)"
  choices = []
  choices << "3"
  choices << "9"
  choices << "27"
  choices << "50"
  choices << "100"
  list << choices.join("|")
  defaults << (permeabilidadHuecos.empty? ? choices.last : permeabilidadHuecos )

  input = UI.inputbox(prompts, defaults, list, "User input.")
  
  zonaClimatica = input[0]
  if lZ.getClimateZones('CTE').empty?
    lZ.appendClimateZone('CTE', zonaClimatica)
  else
    lZ.getClimateZone('CTE', 0).setValue(zonaClimatica)
  end
  epw_path = "#{File.dirname(__FILE__)}/src/epw/" + ( zonaClimatica.include?('c') || zonaClimatica.include?('alpha') ? "#{zonaClimatica.sub('c', '')}_canarias" : "#{zonaClimatica}_peninsula" ) + ".epw"
  epw_file = OpenStudio::EpwFile.new(epw_path)
  OpenStudio::Model::WeatherFile::setWeatherFile(os_model, epw_file)
  
  residencialOTerciario = input[1]
  os_model.building.get.setStandardsBuildingType(nuevoOExistente + "-" + residencialOTerciario)

  permeabilidadHuecos = input[2]
  if lZ.getClimateZones('PermeabilidadHuecos').empty?
    lZ.appendClimateZone('PermeabilidadHuecos', permeabilidadHuecos)
  else
    lZ.getClimateZone('PermeabilidadHuecos', 0).setValue(permeabilidadHuecos)
  end

end