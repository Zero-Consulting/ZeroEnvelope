
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

  input = UI.inputbox(prompts, defaults, list, "User input.")

  unless zonaClimatica.eql?(input[0]) then
    zonaClimatica = input[0]
    epw_file_name = ( zonaClimatica.include?('c') || zonaClimatica.include?('alpha') ? "#{zonaClimatica.sub('c', '')}_canarias" : "#{zonaClimatica}_peninsula" ) + ".epw"
    epw_path = "#{File.dirname(__FILE__)}/src/epw/" + epw_file_name

    osm_path = Plugin.model_manager.model_interface.openstudio_path
    osw_path = osm_path.gsub(".osm", "/workflow.osw")
    osw = OpenStudio::WorkflowJSON.load(osw_path).get.clone
    FileUtils.copy_entry(epw_path, osm_path.gsub(".osm", "/files/") + epw_file_name, remove_destination = true)
    osw.setWeatherFile(epw_file_name)
    osw.saveAs(osw_path)

    UI.messagebox("Successfully set weather file to #{epw_file_name}.")

    Plugin.model_manager.open_openstudio(osm_path, su_model)

    os_model = Plugin.model_manager.model_interface.openstudio_model

    lZ = os_model.getClimateZones
    if lZ.getClimateZones('CTE').empty?
      lZ.appendClimateZone('CTE', zonaClimatica)
    else
      lZ.getClimateZone('CTE', 0).setValue(zonaClimatica)
    end

    epw_file = OpenStudio::EpwFile.new(epw_path)
    weather_lat = epw_file.latitude
    weather_lon = epw_file.longitude
    weather_time = epw_file.timeZone
    weather_elev = epw_file.elevation

    # Add or update site data
    site = os_model.getSite
    site.setName(epw_file_name)
    site.setLatitude(weather_lat)
    site.setLongitude(weather_lon)
    site.setTimeZone(weather_time)
    site.setElevation(weather_elev)
  end

  residencialOTerciario = input[1]
  os_model.building.get.setStandardsBuildingType(nuevoOExistente + "-" + residencialOTerciario)

end