require "#{File.dirname(__FILE__)}/src/geom2d"
require "#{File.dirname(__FILE__)}/src/Constructions"

module OpenStudio
  
  su_model = Sketchup.active_model
  os_model = Plugin.model_manager.model_interface.openstudio_model
  os_path = Plugin.model_manager.model_interface.openstudio_path
  
  # sketchup components for rendering
  
  new_groups, os2su = [], {}
  
  # sg save data
   
  epw_file = nil
  while true do
    weather_file = os_model.getOptionalWeatherFile
    break if weather_file.empty?
    weather_file_path = weather_file.get.path
    break if weather_file_path.empty?
    weather_file_path = os_model.workflowJSON.findFile(weather_file_path.get)
    break if weather_file_path.empty?
    weather_file_path = weather_file_path.get
    weather_file = EpwFile.load(weather_file_path)
    break if weather_file.empty?
    epw_file = weather_file.get
    break
  end
   
  residencialOTerciario = nil
  while true do
    standards_building_type = os_model.building.get.standardsBuildingType()
    break if standards_building_type.empty?
    
    aux = standards_building_type.get.split("-").map do |x| x.strip() end
    break unless aux.length.eql?(3)
    
    residencialOTerciario = aux[1]
    break
  end
  
  permeabilidadHuecos = os_model.getClimateZones.getClimateZone('PermeabilidadHuecos', 0).value
  
  if epw_file.nil? || residencialOTerciario.nil?  || permeabilidadHuecos.empty? then
    load(File.dirname(__FILE__)+"/CaracteristicasEdificio.rb")
    
    epw_file = EpwFile.load(os_model.workflowJSON.findFile(os_model.getOptionalWeatherFile.get.path.get).get).get
    residencialOTerciario = (os_model.building.get.standardsBuildingType().get.split("-").map do |x| x.strip() end)[1]
    permeabilidadHuecos = os_model.getClimateZones.getClimateZone('PermeabilidadHuecos', 0).value
  end

  # ISO 52010
  
  fij_table = [
    [-0.008, 0.588, -0.062, -0.06, 0.072, -0.022],
    [0.13, 0.683, -0.151, -0.019, 0.066, -0.029],
    [0.33, 0.487, -0.221, 0.055, -0.064, -0.026],
    [0.568, 0.187, -0.295, 0.109, -0.152, -0.014],
    [0.873, -0.392, -0.362, 0.226, -0.462, 0.001],
    [1.132, -1.237, -0.412, 0.288, -0.823, 0.056],
    [1.06, -1.6, -0.359, 0.264, -1.127, 0.131],
    [0.678, -0.327, -0.25, 0.156, -1.377, 0.251]
  ]
  
  t_shift = os_model.getSite.timeZone - os_model.getSite.longitude / 15
  phi_w = Utilities.convert(os_model.getSite.latitude, "deg", "rad")
  
  @@sun_phis, @@sun_thetas, @@g_sol_bs, @@g_sol_ds, @@bs, @@f1s, @@f2s = [], [], [], [], [], [], []
  epw_file.data.each do |row|
    next unless row.month.eql?(7)
    
    g_sol_d = Utilities.convert(row.diffuseHorizontalRadiation.get, "W", "kW") # kWh/m2
    g_sol_b = Utilities.convert(row.directNormalRadiation.get, "W", "kW") # kWh/m2
    next unless Geom2D::Utils.float_compare(g_sol_b + g_sol_d, 0) > 0
    
    n_day = row.date.dayOfYear
    r_dc = Utilities.convert(360.0 / 365 * n_day, "deg", "rad")
    
    t_eq = 0.258 * Math.cos(r_dc) - 7.416 * Math.sin(r_dc) - 3.648 * Math.cos(2*r_dc) - 9.228 * Math.sin(2*r_dc)
    # t_eq = if n_day < 21 then
      # 2.6 + 0.44*n_day
    # elsif n_day < 136
      # 5.2 + 9*Math.cos((n_day-43)*0.0357)
    # elsif n_day < 241
      # 1.4 - 5*Math.cos((n_day-135)*0.0449)
    # elsif n_day < 336
      # -6.3-10*Math.cos((n_day-306)*0.036)
    # else 
      # 0.45 * (n_day-359)
    # end
    
    solar_declination = Utilities.convert(0.33281-22.984*Math.cos(r_dc)-0.3499*Math.cos(2*r_dc)-0.1398*Math.cos(3*r_dc)+3.7872*Math.sin(r_dc)+0.03205*Math.sin(2*r_dc)+0.07187*Math.sin(3*r_dc), "deg", "rad")
    
    t_sol = row.hour - Utilities.convert(t_eq, "min", "h") - t_shift
    
    omega_deg = 180.0 / 12 * (12.5 - t_sol)
    omega_deg -= 360 if omega_deg > 180
    omega_deg += 360 if omega_deg < -180
    omega_rad = Utilities.convert(omega_deg, "deg", "rad")
    
    alpha_sol_deg = Utilities.convert(Math.asin(Math.sin(solar_declination)*Math.sin(phi_w) + Math.cos(solar_declination)*Math.cos(phi_w)*Math.cos(omega_rad)), "rad", "deg")
    alpha_sol_deg = 0 if alpha_sol_deg < 1e-4
    alpha_sol_rad = Utilities.convert(alpha_sol_deg, "deg", "rad")
    
    sun_theta_deg = Utilities.convert(Math.acos((Math.sin(solar_declination)*Math.cos(phi_w) - Math.cos(solar_declination)*Math.sin(phi_w)*Math.cos(omega_rad)) / Math.cos(alpha_sol_rad)), "rad", "deg")
    sun_theta_deg = 360 - sun_theta_deg if Geom2D::Utils.float_compare(omega_rad, 0) > 0
    # sin_phi_sol_aux1 = Math.cos(solar_declination) * Math.sin(Math::PI-omega_rad) / Math.cos(Math.asin(Math.sin(alpha_sol_rad)))
    # cos_phi_sol_aux1 = (Math.cos(phi_w)*Math.sin(solar_declination) + Math.sin(phi_w)*Math.cos(solar_declination)*Math.cos(Math::PI-omega_rad)) / Math.cos(Math.asin(Math.sin(alpha_sol_rad)))
    # phi_sol_aux2_deg = Utilities.convert(Math.asin(Math.cos(solar_declination) * Math.sin(Math::PI-omega_rad)) / Math.cos(Math.asin(Math.sin(alpha_sol_rad))), "rad", "deg")
    # phi_sol_deg = if Geom2D::Utils.float_compare(sin_phi_sol_aux1, 0) > -1 && Geom2D::Utils.float_compare(cos_phi_sol_aux1, 0) > 0 then
      # 180 - phi_sol_aux2_deg
    # elsif Geom2D::Utils.float_compare(cos_phi_sol_aux1, 0) < 0 then
      # phi_sol_aux2_deg
    # else
      # - (180 + phi_sol_aux2_deg)
    # end
    
    aux = 1.014 * alpha_sol_rad**3
    epsilon = ( Geom2D::Utils.float_compare(g_sol_d, 0) != 0  ? ((g_sol_d+g_sol_b)/g_sol_d + aux) / (1 + aux) : 999 )
    
    m = 1.0 / ( alpha_sol_deg < 10 ? Math.sin(alpha_sol_rad)+0.15*(alpha_sol_deg+3.885)**-1.253 : Math.sin(alpha_sol_rad) )
    i_ext = Utilities.convert(1370.0, "W", "kW") * (1 + 0.033 * Math.cos(r_dc))
    sky_brightness = m * g_sol_d / i_ext
    
    theta_z_rad = Utilities.convert(90 - alpha_sol_deg, "deg", "rad")
    fij_coeffs = fij_table[[epsilon, 1.065, 1.23, 1.5, 1.95, 2.8, 4.5, 6.2].sort.index(epsilon)]
     
    @@sun_phis << alpha_sol_rad
    @@sun_thetas << Utilities.convert(360 - sun_theta_deg, "deg", "rad")
    # @@sun_thetas << Utilities.convert(180 - phi_sol_deg, "deg", "rad")
    @@g_sol_bs << g_sol_b
    @@g_sol_ds << g_sol_d
    @@bs << [Math.cos(Utilities.convert(85, "deg", "rad")), Math.cos(theta_z_rad)].max
    @@f1s << [0, fij_coeffs[0] + fij_coeffs[1]*sky_brightness + fij_coeffs[2]*theta_z_rad].max
    @@f2s << fij_coeffs[3] + fij_coeffs[4]*sky_brightness + fij_coeffs[5]*theta_z_rad
  end
  @@july_ground_reflectance = os_model.getSiteGroundReflectance.julyGroundReflectance
  
  # sketchup dialog
  
  inputbox_file = "#{File.dirname(__FILE__)}/qsolar/qsolar.html"
  dialog = UI::HtmlDialog.new({:dialog_title => "q solar", :preferences_key => "com.example.html-input", :scrollable => true, :resizable => false, :style => UI::HtmlDialog::STYLE_DIALOG})
  dialog.set_size(1500, 600)
  dialog.set_file(inputbox_file)
  
  os_type = {
    "glazings" => "SimpleGlazing",
    "frames" => "WindowPropertyFrameAndDivider",
    "shades" => "Shade"
  }

  standards_information_hash = {
    "intended_surface_type" => [""] + OpenStudio::Model::StandardsInformationConstruction.intendedSurfaceTypeValues.select do |x| x.include?("Window") || x.include?("Skylight") || x.include?("Door") end,
    "fenestration_type" => [""] + OpenStudio::Model::StandardsInformationConstruction.fenestrationTypeValues,
    "fenestration_frame_type" => [""] + OpenStudio::Model::StandardsInformationConstruction.fenestrationFrameTypeValues
  }

  dialog.add_action_callback("load") do |action_context|
    script = []
    
    script += Constructions.add_interface_objects(os_model, os_type)

    standards_information_hash.each do |id, options|
      script << "var select = document.getElementById('#{id}')"
      options.each do |option|
        script << "var option = document.createElement('option')"
        script << "option.innerHTML = '#{option}'"
        script << "select.appendChild(option)"
      end
    end
    
    script << "var shade_select = document.getElementById('shade_type')"
    OpenStudio::Model::ShadingControl.shadingTypeValues.each do |shading_type|
      case
      when shading_type.end_with?("Shade")
        option = shading_type.split("Shade")[0]
        script << "var option = document.createElement('option')"
        script << "option.value = '#{option.downcase}'"
        script << "option.innerHTML = '#{option}'"
        script << "shade_select.appendChild(option)"
      end
    end
 
    dialog.execute_script(script.join(";"))
  end
  
  @@render = "openstudio"
  @@outdoor_sub_surfaces = os_model.getSubSurfaces.select do |sub_surface| 
    sub_surface.outsideBoundaryCondition.eql?("Outdoors")
  end.sort_by do |sub_surface|
    sub_surface.name.get.to_s.split("Sub Surface ").last.to_i
  end
  
  dialog.add_action_callback("render_white") do |action_context|
    @@outdoor_sub_surfaces.each do |sub_surface|
      face = @@os2su[sub_surface]
      color = Sketchup::Color.new(255, 255, 255, 1.0)
      face.material = color
      face.back_material = color
    end if @@render.eql?("input")
  end
  
  def self.render_by_selection(id, li_object)
    @@outdoor_sub_surfaces.each do |sub_surface|
      aux = case id
      when "glazings"
        sub_surface.construction
      when "frames"
        sub_surface.windowPropertyFrameAndDivider
      when "shades"
        sub_surface.shadingControl
      end
      
      color = if aux.empty? then
        Sketchup::Color.new(96, 80, 76, 1.0)
      elsif aux.get.eql?(li_object) then
        Sketchup::Color.new(120, 157, 74, 1.0)
      else
        Sketchup::Color.new(255, 255, 255, 1.0)
      end

      face = @@os2su[sub_surface]
      face.material = color
      face.back_material = color
    end
  end
  
  def self.get_window_with_frame_area(sub_surface, frame_width)
    coordinates, normal_k = ["x", "y", "z"], sub_surface.outwardNormal
    max_normal, max_coordinate = coordinates.map do |coordinate|
      eval("[normal_k.#{coordinate}.abs, coordinate]")
    end.sort.max
    plane_coordinates = coordinates - [max_coordinate]
    
    vertices = sub_surface.vertices
    new_vertices = vertices.each_with_index.map do |vertex, index|
      edge_i, edge_j = [vertices[(index+1) % vertices.length], vertex], [vertex, vertices[index-1]]
      
      normal_i = (edge_i.last - edge_i.first).cross(normal_k)
      normal_i.setLength(1)
      normal_j = (edge_j.last - edge_j.first).cross(normal_k)                
      normal_j.setLength(1)

      normal_u = normal_i
      normal_v = normal_j
      normal_w = normal_k
      detA = normal_u.dot(normal_v.cross(normal_w))
      
      normal_u = OpenStudio::Vector3d.new(-frame_width, normal_i.y, normal_i.z)
      normal_v = OpenStudio::Vector3d.new(-frame_width, normal_j.y, normal_j.z)
      normal_w = OpenStudio::Vector3d.new(0.0, normal_k.y, normal_k.z)
      detAu = normal_u.dot(normal_v.cross(normal_w))
      
      normal_u = OpenStudio::Vector3d.new(normal_i.x, -frame_width, normal_i.z)
      normal_v = OpenStudio::Vector3d.new(normal_j.x, -frame_width, normal_j.z)
      normal_w = OpenStudio::Vector3d.new(normal_k.x, 0.0, normal_k.z)
      detAv = normal_u.dot(normal_v.cross(normal_w))
      
      normal_u = OpenStudio::Vector3d.new(normal_i.x, normal_i.y, -frame_width)
      normal_v = OpenStudio::Vector3d.new(normal_j.x, normal_j.y, -frame_width)
      normal_w = OpenStudio::Vector3d.new(normal_k.x, normal_k.y, 0.0)
      detAw = normal_u.dot(normal_v.cross(normal_w))
      
      vertex + OpenStudio::Vector3d.new(detAu/detA, detAv/detA, detAw/detA)
    end

    area =  new_vertices.each_with_index.map do |vertex, index|
      eval("vertex.#{plane_coordinates.first} * (new_vertices[(index+1) % new_vertices.length].#{plane_coordinates.last}-new_vertices[index-1].#{plane_coordinates.last})")
    end.inject(0.0) do |sum, x| sum + x end.abs / max_normal / 2
    
    return area
  end
  
  dialog.add_action_callback("show_li") do |action_context, id, li|
    script = []
        
    li_object = nil
    case id      
    when "glazings"
      simple_glazing = os_model.getSimpleGlazingByName(li).get
      script << "document.getElementById('ufactor').value = parseFloat(#{simple_glazing.uFactor}).toFixed(2)"
      script << "document.getElementById('shgc').value = parseFloat(#{simple_glazing.solarHeatGainCoefficient}).toFixed(2)"
      vlt = simple_glazing.visibleTransmittance
      script << "document.getElementById('vlt').value = #{ !vlt.empty? ? "parseFloat(#{vlt.get}).toFixed(2)" : "null" }"
      
      li_object = os_model.getLayeredConstructionByName(li).get
      standards_information = li_object.standardsInformation
      standards_information_hash.each do |id, options|
        type = nil
        eval("type = standards_information.#{Utilities.capitalize_all_but_first(id)}")
        script << "document.getElementById('#{id}').selectedIndex = '#{ type.empty? ? 0 : options.find_index(type.get) }'"
      end
      
    when "frames"
      li_object = os_model.getWindowPropertyFrameAndDividerByName(li).get
      script << "document.getElementById('frame_width').value = parseFloat(#{li_object.frameWidth*100}).toFixed(0)"
      frame_conductance = li_object.frameConductance
      script << "document.getElementById('frame_conductance').value = #{ frame_conductance.empty? ? "null" : "parseFloat(#{frame_conductance.get}).toFixed(1)"}"
      script << "document.getElementById('frame_setback').value = parseFloat(#{li_object.outsideRevealDepth*100}).toFixed(0)"
      frame_reflectance = li_object.additionalProperties.getFeatureAsDouble("frame_reflectance")
      if frame_reflectance.empty? then
        script << "document.getElementById('frame_colour').value = -1"
        script << "document.getElementById('frame_reflectance').readOnly = false"
      else
        script << "document.getElementById('frame_colour').value = #{frame_reflectance.get.round(1)}"
        script << "document.getElementById('frame_reflectance').readOnly = true"
      end
      frame_reflectance = 1 - li_object.frameSolarAbsorptance
      script << "document.getElementById('frame_reflectance').value = parseFloat(#{frame_reflectance}).toFixed(1)"
      
    when "shades"
      li_object = os_model.getShadingControlByName(li).get
      shade = os_model.getShadeByName(li).get
      script << "document.getElementById('shade_type').value = '#{li_object.shadingType.split("Shade")[0].downcase}'"
      openness_fraction = shade.additionalProperties.getFeatureAsDouble("openness_fraction")
      if openness_fraction.empty? then
        script << "document.getElementById('shade_material').value = -1"
        script << "document.getElementById('shade_openness_fraction').readOnly = false"
      else
        script << "document.getElementById('shade_material').value = #{openness_fraction.get.round(1)}"
        script << "document.getElementById('shade_openness_fraction').readOnly = true"
      end
      openness_fraction = shade.thermalTransmittance
      script << "document.getElementById('shade_openness_fraction').value = parseFloat(#{openness_fraction}).toFixed(1)"
      yarn_reflectance = shade.additionalProperties.getFeatureAsDouble("yarn_reflectance")
      if yarn_reflectance.empty? then
        script << "document.getElementById('shade_colour').value = -1"
        script << "document.getElementById('shade_yarn_reflectance').readOnly = false"
      else
        script << "document.getElementById('shade_colour').value = #{yarn_reflectance.get.round(1)}"
        script << "document.getElementById('shade_yarn_reflectance').readOnly = true"
      end
      solar_reflectance = shade.solarReflectance
      yarn_reflectance = solar_reflectance / (1 - openness_fraction)
      script << "document.getElementById('shade_yarn_reflectance').value = parseFloat(#{yarn_reflectance}).toFixed(1)"
      script << "document.getElementById('shade_transmittance').value = parseFloat(#{shade.solarTransmittance}).toFixed(2)"
      script << "document.getElementById('shade_reflectance').value = parseFloat(#{solar_reflectance}).toFixed(2)"
      setpoint = li_object.setpoint.get
      script << "document.getElementById('shade_control').value = '#{setpoint.round(0)}'"
      script << "document.getElementById('shade_setpoint').value = parseFloat(#{setpoint}).toFixed(0)"
    end

    self.render_by_selection(id, li_object) if @@render.eql?("input")
    
    dialog.execute_script(script.join(";"))
  end

  def self.update_shade(shade)
    openness_fraction = shade.thermalTransmittance
    solar_reflectance = shade.solarReflectance
    
    b = 1.428*openness_fraction + 0.178    
    solar_transmittance = (openness_fraction + 8e-3*solar_reflectance) * (1 + solar_reflectance)**(1/b) # Keyes Universal Chart
    
    shade.setSolarTransmittance(solar_transmittance)
    shade.setVisibleTransmittance(solar_transmittance)
    shade.setThermalHemisphericalEmissivity(0.9 * (1 - openness_fraction))
    shade.setVisibleReflectance(solar_reflectance)
  end
  
  dialog.add_action_callback("add_object") do |action_context, id|    
    script = []
    
    new_object = nil
    eval("new_object = OpenStudio::Model::#{os_type[id]}.new(os_model)")
    new_object.additionalProperties.setFeature("interface", true)
    name = new_object.name.get.to_s
    case id
    when "glazings"
      new_construction = OpenStudio::Model::Construction.new([new_object])
      new_construction.setName(name)
        
    when "shades"
      self.update_shade(new_object)

      new_shading_control = OpenStudio::Model::ShadingControl.new(new_object)
      new_shading_control.setName(name)
      new_shading_control.setSetpoint(300)
    end
    script << "add_li('#{id}', '#{name}')"
          
    dialog.execute_script(script.join(";"))
  end

  dialog.add_action_callback("rename_object") do |action_context, id, old_name, new_name|    
    script = []
    
    old_name, new_name = self.fix_name(old_name), self.fix_name(new_name)
    object = nil
    eval("object = os_model.get#{os_type[id]}ByName(old_name).get")
    object.setName(new_name)
    name = object.name.get.to_s
    aux_os_type = case id
    when "glazings"
      "Construction"
      
    when "shades"
      "ShadingControl"
    end
    eval("os_model.get#{aux_os_type}ByName(old_name).get.setName(new_name)") unless aux_os_type.nil?
    script << "document.getElementById('old_name').parentNode.innerHTML = '#{name}'"
      
    dialog.execute_script(script.join(";"))
  end
  
  dialog.add_action_callback("duplicate_object") do |action_context, id, object_name|    
    script = []
    
    object_name = self.fix_name(object_name)
    new_object = nil
    eval("new_object = os_model.get#{os_type[id]}ByName(object_name).get.clone(os_model).to_#{os_type[id]}.get")
    new_name = new_object.name.get.to_s
    other_object = case id
    when "glazings"
      OpenStudio::Model::Construction.new([new_object])
    when "shades"
      shading_control = os_model.getShadingControlByName(object_name).get.clone(os_model).to_ShadingControl.get
      shading_control.setString(4, object_name)
      shading_control
    end
    other_object.setName(name) unless other_object.nil?
    script << "add_li('#{id}', '#{new_object.name.get.to_s}')"

    dialog.execute_script(script.join(";"))
  end
  
  def self.render_by_phi_sol_jul()
    @@outdoor_sub_surfaces.map do |sub_surface|
      h_sh_obst_jul_dir = @@h_sh_obst_jul_dirs[sub_surface]
      h_sh_obst_jul_dif = @@h_sh_obst_jul_difs[sub_surface]
      g_gl_sh_wi = @@g_gl_sh_wis[sub_surface]
      phi_sol_jul = (h_sh_obst_jul_dir + h_sh_obst_jul_dif) * sub_surface.grossArea * g_gl_sh_wi
    
      color = Sketchup::Color.new
      h = (1.0 - [phi_sol_jul / (3 * (@@q_sol_jul_lim * @@total_floor_area) / @@outdoor_sub_surfaces.length), 1.0].min) * 120
      OpenStudio::set_hsba(color, [h, 100, 100, 1.0])

      face = @@os2su[sub_surface]
      face.material = color
      face.back_material = color
    end
  end
  
  def self.get_g_gl_sh_wi(sub_surface)
    glass_construction = sub_surface.construction
    return 1 if glass_construction.empty?
    glass_construction = glass_construction.get
    return 1 unless glass_construction.isFenestration
    layered_construction = glass_construction.to_LayeredConstruction
    return 1 if layered_construction.empty?
    layers = layered_construction.get.layers
    return 1 if layers.empty?
    simple_glazing = layers[0].to_SimpleGlazing
    return 1 if simple_glazing.empty?
    simple_glazing = simple_glazing.get
    
    glass_u_factor = simple_glazing.uFactor
    g_gl_n = simple_glazing.solarHeatGainCoefficient
    g_gl_wi = 0.9 * g_gl_n

    shading_control = sub_surface.shadingControl 
    return g_gl_wi if shading_control.empty?
    shading_control = shading_control.get
    shading_type = shading_control.shadingType
    return g_gl_wi unless shading_type.end_with?("Shade")

    shade = shading_control.shadingMaterial.get.to_Shade.get
    transmittance, reflectance = shade.thermalTransmittance, shade.solarReflectance

    case shading_type
    when "ExteriorShade"
      g_1, g_2 = 5, 10
      g_ext = 1 / (1/glass_u_factor + 1/g_1 + 1/g_2)
      return transmittance*g_gl_n + (1-transmittance-reflectance)*g_ext/g_2 + transmittance*(1-g_gl_n)*g_ext/g_1
      
    when "InteriorShade"
      g_3 = 30
      g_int = 1 / (1/glass_u_factor + 1/g_3)
      return g_gl_n * (1 - g_gl_n*reflectance - (1-transmittance-reflectance)*g_int/g_3)
      
    when "BetweenGlassShade", "BetweenglassShade"
      g_4 = 3
      g_integr = 1 / (1/glass_u_factor + 1/g_4)
      return g_gl_n*transmittance + g_gl_n*((1-transmittance-reflectance) + (1-g_gl_n)*reflectance)*g_integr/g_4
    end # UNE 52022
    
    return 1
  end
  
  @@q_sol_jul_lim = case residencialOTerciario
  when "Residencial"
    2.0
    
  else
    4.0
  end
  
  def self.update_g_gl_sh_wi(sub_surface, index)   
    script = []
    
    return script if @@total_phi_sol_jul.nil?
    
    script << "var cells = document.getElementsByTagName('tbody')[0].rows[#{index}].cells"
    
    area = sub_surface.grossArea
    h_sh_obst_jul_dir = @@h_sh_obst_jul_dirs[sub_surface]
    h_sh_obst_jul_dif = @@h_sh_obst_jul_difs[sub_surface]
    
    @@total_phi_sol_jul -= (h_sh_obst_jul_dir + h_sh_obst_jul_dif) * area * @@g_gl_sh_wis[sub_surface]
    g_gl_sh_wi = self.get_g_gl_sh_wi(sub_surface)
    script << "cells[6].innerHTML = parseFloat(#{g_gl_sh_wi}).toFixed(1)"
    @@g_gl_sh_wis[sub_surface] = g_gl_sh_wi
    phi_sol_jul = (h_sh_obst_jul_dir + h_sh_obst_jul_dif) * area * g_gl_sh_wi
    script << "cells[7].innerHTML = parseFloat(#{phi_sol_jul}).toFixed(2)"
    @@total_phi_sol_jul += phi_sol_jul
    script << "var q_sol_jul = document.querySelectorAll('#qsoljul input')[0]"
    q_sol_jul = @@total_phi_sol_jul / @@total_floor_area
    script << "q_sol_jul.value = parseFloat(#{q_sol_jul}).toFixed(2)"
    script << "q_sol_jul.style.color = '#{ q_sol_jul > @@q_sol_jul_lim ? "red" : nil }'"
    
    self.render_by_phi_sol_jul if @@render.eql?("output")
    
    return script
  end
  
  def self.get_sunlit_area(frame_setback, sun_direction, normal, sub_surface_vertices, sub_surfaces_transformation, sub_surface_sunlit)
    sunlit = if Geom2D::Utils.float_compare(frame_setback, 0) > 0 then
      alpha = - frame_setback / sun_direction.dot(normal)
      sun_direction.setLength(alpha)
      sun_direction = sun_direction.reverseVector
      
      vertices = sub_surface_vertices.map do |vertex| vertex + sun_direction end
      sub_surface_polygon = Geom2D::Polygon.new((sub_surfaces_transformation.inverse * vertices).map do |vertex| [vertex.x, vertex.y] end)
      Geom2D::Algorithms::PolygonOperation.run(Geom2D::PolygonSet.new([sub_surface_polygon]), sub_surface_sunlit, :intersection)
    else
      sub_surface_sunlit
    end
    
    return sunlit.area
  end
  
  phis_length = 6
  @@phis = phis_length.times.map do |x| 90.0 / phis_length * x + 45.0 / phis_length end.unshift(0).push(90).map do |phi| Utilities.convert(phi, "deg", "rad") end
  thetas_length = 24
  @@thetas = thetas_length.times.to_a.map do |x| 360.0 / thetas_length * x end.map do |theta| Utilities.convert(theta, "deg", "rad") end
  
  def self.get_h_sol_jul(sub_surface, obst)
    @@coplanar_outdoor_sub_surfaces.each do |plane, plane_hash|
      sub_surfaces = plane_hash["sub_surfaces"]
      next unless sub_surfaces.include?(sub_surface)
      normal = plane.outwardNormal
      sub_surfaces_transformation = OpenStudio::Transformation.alignFace(sub_surfaces.first.space.get.transformation * sub_surfaces.first.vertices)
      
      frame_setback, sub_surface_vertices = 0, nil
      sunlit_fractions = if obst then        
        while true
          frame = sub_surface.windowPropertyFrameAndDivider 
          break if frame.empty?
          frame_setback = frame.get.outsideRevealDepth
          break
        end
        
        diffuse_sunlit_vertices = @@sub_surface2sunlit_vertices[sub_surface]["diffuse"]
        sub_surface_vertices = sub_surface.space.get.transformation * sub_surface.vertices
        @@phis.each_with_index.map do |phi, j|
          @@thetas.each_with_index.map do |theta, i|
            sub_surface_sunlit = diffuse_sunlit_vertices[j][i]
            if Geom2D::Utils.float_compare(sub_surface_sunlit.area, 0) > 0 then
              sun_direction = OpenStudio::Vector3d.new(Math.cos(phi)*Math.sin(theta), Math.cos(phi)*Math.cos(theta), Math.sin(phi)).reverseVector
              
              self.get_sunlit_area(frame_setback, sun_direction, normal, sub_surface_vertices, sub_surfaces_transformation, sub_surface_sunlit) / sub_surface.grossArea
            else
              0.0
            end
          end
        end
      end
      
      r_horizon = unless sunlit_fractions.nil? then
        sum_irr_sf, sum_irr = 0, 0
        @@thetas.each_with_index do |theta, i|
          cos_alpha_i = normal.dot(OpenStudio::Vector3d.new(Math.sin(theta), Math.cos(theta), 0))
          next if Geom2D::Utils.float_compare(cos_alpha_i, 0) < 1
          irr = (2 * Math::PI / @@thetas.length) * cos_alpha_i
          sum_irr_sf += irr * sunlit_fractions[0][i]
          sum_irr += irr
        end
        
        Geom2D::Utils.float_compare(sum_irr, 0) == 0 ? 0 : sum_irr_sf / sum_irr
      else
        1
      end

      r_dome = unless sunlit_fractions.nil? then
        sum_irr_sf, sum_irr = 0, 0
        @@phis.each_with_index.map do |phi, j|
          next if j.eql?(0) || (j+1).eql?(@@phis.length)
          @@thetas.each_with_index.map do |theta, i|
            cos_alpha_ij = normal.dot(OpenStudio::Vector3d.new(Math.cos(phi)*Math.sin(theta), Math.cos(phi)*Math.cos(theta), Math.sin(phi)))
            next if Geom2D::Utils.float_compare(cos_alpha_ij, 0) < 1
            irr = Math.cos(phi) * (2 * Math::PI / @@thetas.length) * (Math::PI / 2 / @@phis.length) * cos_alpha_ij
            sum_irr_sf += irr * sunlit_fractions[j][i]
            sum_irr += irr
          end
        end
        
        Geom2D::Utils.float_compare(sum_irr, 0) == 0 ? 0 : sum_irr_sf / sum_irr
      else
        1
      end
      
      beta_ic_rad = sub_surface.tilt
      h_sol_jul_dir, h_sol_jul_dif = 0, 0
      @@sun_thetas.zip(@@sun_phis, @@g_sol_bs, @@g_sol_ds, @@bs, @@f1s, @@f2s, @@sub_surface2sunlit_vertices[sub_surface]["direct"]).each do |sun_theta, sun_phi, g_sol_b, g_sol_d, b, f1, f2, sub_surface_sunlit|        
        cos_theta_sol_ic = normal.dot(OpenStudio::Vector3d.new(Math.cos(sun_phi)*Math.sin(sun_theta), Math.cos(sun_phi)*Math.cos(sun_theta), Math.sin(sun_phi)))
        
        sf = unless sunlit_fractions.nil? then
          if Geom2D::Utils.float_compare(sub_surface_sunlit.area, 0) > 0 then
            sun_direction = OpenStudio::Vector3d.new(Math.cos(sun_phi)*Math.sin(sun_theta), Math.cos(sun_phi)*Math.cos(sun_theta), Math.sin(sun_phi)).reverseVector
            
            self.get_sunlit_area(frame_setback, sun_direction, normal, sub_surface_vertices, sub_surfaces_transformation, sub_surface_sunlit) / sub_surface.grossArea
          else
            0.0
          end
        else
          Geom2D::Utils.float_compare(cos_theta_sol_ic, 0) > 0 ? 1 : 0
        end
        
        a = [0, cos_theta_sol_ic].max
        i_circum = g_sol_d * f1 * a / b
        h_sol_jul_dir += (g_sol_b * a + i_circum) * sf
        
        i_horizon = g_sol_d * f2 * Math.sin(beta_ic_rad)
        i_dome =  g_sol_d * (1 - f1) * (1 + Math.cos(beta_ic_rad)) / 2
        i_ground = (g_sol_d + g_sol_b * Math.sin(sun_phi)) * @@july_ground_reflectance * (1 - Math.cos(beta_ic_rad)) / 2
        h_sol_jul_dif += i_horizon * r_horizon + i_dome * r_dome + i_ground        
      end
      
      return h_sol_jul_dir, h_sol_jul_dif
    end
    
    return 0, 0
  end
  
  def self.update_h_sh_obst_jul(sub_surface, index)
    script = []
    
    return script if @@total_phi_sol_jul.nil?
    
    script << "var cells = document.getElementsByTagName('tbody')[0].rows[#{index}].cells"
    
    area = sub_surface.grossArea
    g_gl_sh_wi = @@g_gl_sh_wis[sub_surface]
    
    @@total_phi_sol_jul -= (@@h_sh_obst_jul_dirs[sub_surface] + @@h_sh_obst_jul_difs[sub_surface]) * area * g_gl_sh_wi
    h_sh_obst_jul_dir, h_sh_obst_jul_dif = self.get_h_sol_jul(sub_surface, true)
    
    script << "cells[4].innerHTML = parseFloat(#{h_sh_obst_jul_dir} / parseFloat(cells[2].innerHTML)).toFixed(1)"
    @@h_sh_obst_jul_dirs[sub_surface] = h_sh_obst_jul_dir
    script << "cells[5].innerHTML = parseFloat(#{h_sh_obst_jul_dif} / parseFloat(cells[3].innerHTML)).toFixed(1)"
    @@h_sh_obst_jul_difs[sub_surface] = h_sh_obst_jul_dif
    phi_sol_jul = (h_sh_obst_jul_dir + h_sh_obst_jul_dif) * area * g_gl_sh_wi
    script << "cells[7].innerHTML = parseFloat(#{phi_sol_jul}).toFixed(2)"
    @@total_phi_sol_jul += phi_sol_jul
    script << "var q_sol_jul = document.querySelectorAll('#qsoljul input')[0]"
    q_sol_jul = @@total_phi_sol_jul / @@total_floor_area
    script << "q_sol_jul.value = parseFloat(#{q_sol_jul}).toFixed(2)"
    script << "q_sol_jul.style.color = '#{ q_sol_jul > @@q_sol_jul_lim ? "red" : nil }'"
    
    self.render_by_phi_sol_jul if @@render.eql?("output")
    
    return script
  end
  
  dialog.add_action_callback("edit_object") do |action_context, left_id, object_name, input_id, value|
    script = []
    
    case input_id
    when "ufactor", "shgc", "vlt"
      glazing = os_model.getSimpleGlazingByName(object_name).get
      case input_id
      when "ufactor"
        glazing.setUFactor(value)
        
      when "shgc"
        glazing.setSolarHeatGainCoefficient(value)
        
      when "vlt"
        glazing.setVisibleTransmittance(value)
      end
      
      case input_id
      when "ufactor", "shgc"
        @@outdoor_sub_surfaces.each_with_index do |sub_surface, index|
          glass_construction = sub_surface.construction
          next if glass_construction.empty?
          glass_construction = glass_construction.get
          next unless glass_construction.isFenestration
          layered_construction = glass_construction.to_LayeredConstruction
          next if layered_construction.empty?
          layers = layered_construction.get.layers
          next if layers.empty?
          simple_glazing = layers[0].to_SimpleGlazing
          next if simple_glazing.empty?
          next unless simple_glazing.get.eql?(glazing)
          
          script += self.update_g_gl_sh_wi(sub_surface, index)
        end unless @@total_phi_sol_jul.nil?
      end
      
    when "intended_surface_type", "fenestration_type", "fenestration_frame_type"
      standards_information = os_model.getLayeredConstructionByName(object_name).get.standardsInformation
      case input_id
      when "intended_surface_type"
        standards_information.setIntendedSurfaceType(value)
        
      when "fenestration_type"
        standards_information.setFenestrationType(value)
        
      when "fenestration_frame_type"
        standards_information.setFenestrationFrameType(value)
      end
      
    when "frame_width", "frame_conductance", "frame_setback", "frame_colour", "frame_reflectance"
      frame = os_model.getWindowPropertyFrameAndDividerByName(object_name).get
      case input_id
      when "frame_width"
        frame.setFrameWidth(value / 100.0)
        
      when "frame_conductance"
        frame.setFrameConductance(value)
        
      when "frame_setback"
        frame.setOutsideRevealDepth(value / 100.0)
        
        @@outdoor_sub_surfaces.each_with_index do |sub_surface, index|
          window_property_frame_and_divider = sub_surface.windowPropertyFrameAndDivider
          next if window_property_frame_and_divider.empty?
          next unless window_property_frame_and_divider.get.eql?(frame)
          
          script += self.update_h_sh_obst_jul(sub_surface, index)
        end unless @@total_phi_sol_jul.nil?
        
      when "frame_colour"
        value = value.to_f
        if value < 0 then
          frame.additionalProperties.resetFeature("frame_reflectance")
        else
          frame.additionalProperties.setFeature("frame_reflectance", value)
        end
      end
      
      case input_id
      when "frame_colour", "frame_reflectance"
        frame.setFrameSolarAbsorptance(1 - value)
        frame.setFrameVisibleAbsorptance(1 - value)
      end
      
    when "shade_type", "shade_control"
      shading_control = os_model.getShadingControlByName(object_name).get
      case input_id
      when "shade_type"
        shading_control.setShadingType("#{value.capitalize}Shade")
        
        @@outdoor_sub_surfaces.each_with_index do |sub_surface, index|
          sub_surface_shading_control = sub_surface.shadingControl
          next if sub_surface_shading_control.empty?
          next unless sub_surface_shading_control.get.eql?(shading_control)
          
          script += self.update_g_gl_sh_wi(sub_surface, index)
        end unless @@total_phi_sol_jul.nil?
        
      when "shade_control"
        shading_control.setSetpoint(value.to_i)
      end
      
    when "shade_material", "shade_openness_fraction", "shade_colour", "shade_yarn_reflectance"
      shade = os_model.getShadeByName(object_name).get
      
      case input_id
      when "shade_material"
        value = value.to_f
        if value < 0 then
          shade.additionalProperties.resetFeature("openness_fraction")
        else
          shade.additionalProperties.setFeature("openness_fraction", value)
        end      
        
      when "shade_colour"
        value = value.to_f
        if value < 0 then
          shade.additionalProperties.resetFeature("yarn_reflectance")
        else
          shade.additionalProperties.setFeature("yarn_reflectance", value)
        end
      end
      
      case input_id
      when "shade_material", "shade_openness_fraction"
        shade.setSolarReflectance(shade.solarReflectance * (1 - value) / (1 - shade.thermalTransmittance))
        shade.setThermalTransmittance(value)
      
      when "shade_openness_fraction", "shade_colour"
        shade.setSolarReflectance(value * (1 - shade.thermalTransmittance))
      end
      
      self.update_shade(shade)
      
      @@outdoor_sub_surfaces.each_with_index do |sub_surface, index|
        shading_control = sub_surface.shadingControl
        next if shading_control.empty?
        shading_material = shading_control.get.shadingMaterial
        next if shading_material.empty?
        sub_surface_shade = shading_material.get.to_Shade
        next if sub_surface_shade.empty?
        next unless sub_surface_shade.get.eql?(shade)
        
        script += self.update_g_gl_sh_wi(sub_surface, index)
      end unless @@total_phi_sol_jul.nil?
    end
    
    script << "sketchup.show_li('#{left_id}', '#{object_name}')"
    
    dialog.execute_script(script.join(";"))
  end

  dialog.add_action_callback("remove_object") do |action_context, id, object_name|   
    script = []
    
    object_name = self.fix_name(object_name)
    object = nil
    eval("object = os_model.get#{os_type[id]}ByName(object_name).get")
    case id
    when "frames"
      @@outdoor_sub_surfaces.each_with_index do |sub_surface, index|
        window_property_frame_and_divider = sub_surface.windowPropertyFrameAndDivider
        next if window_property_frame_and_divider.empty?
        next unless window_property_frame_and_divider.get.eql?(object)
        
        sub_surface.resetWindowPropertyFrameAndDivider
        script += self.update_h_sh_obst_jul(sub_surface, index)
      end unless @@total_phi_sol_jul.nil?
    end
    object.remove
    
    aux_os_type = case id
    when "glazings"
      "ConstructionBase"
      
    when "shades"
      "ShadingControl" 
    end
    unless aux_os_type.nil? then
      aux_object = nil
      eval("aux_object = os_model.get#{aux_os_type}ByName(object_name).get")
      case id        
      when "glazings"
        @@outdoor_sub_surfaces.each_with_index do |sub_surface, index|
          construction = sub_surface.construction
          next if construction.empty?
          next unless construction.get.eql?(aux_object)
          
          script += self.update_g_gl_sh_wi(sub_surface, index)
        end unless @@total_phi_sol_jul.nil?
        
      when "shades"
        @@outdoor_sub_surfaces.each_with_index do |sub_surface, index|
          shading_control = sub_surface.shadingControl
          next if shading_control.empty?
          next unless shading_control.get.eql?(aux_object)
          
          sub_surface.resetShadingControl
          script += self.update_g_gl_sh_wi(sub_surface, index)
        end unless @@total_phi_sol_jul.nil?
      end
      aux_object.remove
    end
    
    dialog.execute_script(script.join(";"))
  end
  
  dialog.add_action_callback("assign") do |action_context, id, li|    
    script = []
    
    selection = su_model.selection
    sub_surfaces = if selection.empty? then
      UI.messagebox("Assign to all?", MB_YESNO).eql?(IDYES) ? @@outdoor_sub_surfaces : []
    else
      SketchUp.get_selected_planar_surfaces(os_model).map do |planar_surface|
        sub_surface = planar_surface.to_SubSurface
        next if sub_surface.empty?
        sub_surface = sub_surface.get
      end.compact
    end

    sub_surfaces.each do |sub_surface|  
      case id        
      when "glazings"
        sub_surface.setConstruction(os_model.getLayeredConstructionByName(li).get)
        script << self.update_g_gl_sh_wi(sub_surface, @@outdoor_sub_surfaces.index(sub_surface)) unless @@total_phi_sol_jul.nil?
        
      when "frames"
        sub_surface.setWindowPropertyFrameAndDivider(os_model.getWindowPropertyFrameAndDividerByName(li).get)
        script << self.update_h_sh_obst_jul(sub_surface, @@outdoor_sub_surfaces.index(sub_surface)) unless @@total_phi_sol_jul.nil?
        
      when "shades"
        sub_surface.setShadingControl(os_model.getShadingControlByName(li).get)
        script << self.update_g_gl_sh_wi(sub_surface, @@outdoor_sub_surfaces.index(sub_surface)) unless @@total_phi_sol_jul.nil?
      end
    end
    
    selection.grep(Sketchup::Edge).each do |edge| edge.erase! end
    script << "sketchup.show_li('#{id}', '#{li}')"
    
    dialog.execute_script(script.join(";"))
  end

  dialog.add_action_callback("remove") do |action_context, id, li|    
    script = []
    
    selection = su_model.selection
    sub_surfaces = if selection.empty? then
      UI.messagebox("Remove all?", MB_YESNO).eql?(IDYES) ? @@outdoor_sub_surfaces : []
    else
      SketchUp.get_selected_planar_surfaces(os_model).map do |planar_surface|
        sub_surface = planar_surface.to_SubSurface
        next if sub_surface.empty?
        sub_surface = sub_surface.get
      end.compact
    end

    sub_surfaces.each do |sub_surface|  
      case id        
      when "glazings"
        sub_surface.resetConstruction
        script << self.update_g_gl_sh_wi(sub_surface, @@outdoor_sub_surfaces.index(sub_surface)) unless @@total_phi_sol_jul.nil?
        
      when "frames"
        sub_surface.resetWindowPropertyFrameAndDivider
        script << self.update_h_sh_obst_jul(sub_surface, @@outdoor_sub_surfaces.index(sub_surface)) unless @@total_phi_sol_jul.nil?
        
      when "shades"
        sub_surface.resetShadingControl
        script << self.update_g_gl_sh_wi(sub_surface, @@outdoor_sub_surfaces.index(sub_surface)) unless @@total_phi_sol_jul.nil?
      end
    end
    
    selection.grep(Sketchup::Edge).each do |edge| edge.erase! end
    script << "sketchup.show_li('#{id}', '#{li}')"
    
    dialog.execute_script(script.join(";"))
  end
  
  def self.get_shadow(sun_direction, plane, plane_hash)
    sub_surfaces, fronts = plane_hash["sub_surfaces"], plane_hash["fronts"]
    normal, d = plane.outwardNormal, plane.d
    
    sub_surfaces_transformation = OpenStudio::Transformation.alignFace(sub_surfaces.first.space.get.transformation * sub_surfaces.first.vertices)
    polygons = []
    fronts.each_with_index do |front|
      next if front.nil?
      next if front.empty?

      front_normal = (front.first[1]-front.first[0]).cross(front.first[-1]-front.first[0])
      front_normal.normalize
      next if Geom2D::Utils.float_compare(front_normal.dot(sun_direction), 0) == 0
      front.each do |polygon|
        vertices = polygon.map do |vertex|
          sun_direction.normalize
          alpha = - ((vertex - OpenStudio::Point3d.new).dot(normal) + d) / sun_direction.dot(normal)
          if Geom2D::Utils.float_compare(alpha, 0) < 1  then
            vertex
          else
            sun_direction.setLength(alpha)
            vertex + sun_direction
          end
        end
        sun_direction.normalize
        
        polygon = Geom2D::Polygon.new((sub_surfaces_transformation.inverse * vertices).map do |vertex| [vertex.x, vertex.y] end)
        polygon.reverse! unless polygon.ccw?
        polygons << polygon
      end
    end
                
    shadow = Geom2D::PolygonSet.new
    polygons.each do |polygon| 
      shadow = Geom2D::Algorithms::PolygonOperation.run(shadow, Geom2D::PolygonSet.new([polygon]), :union)
    end
    
    return shadow
  end
  
  new_groups, @@os2su = SketchUp.get_os2su(os_model, true)
  @@new_group = new_groups.first
  @@total_floor_area, @@total_phi_sol_jul = 0.0, nil
  @@h_sh_obst_jul_dirs, @@h_sh_obst_jul_difs, @@g_gl_sh_wis = {}, {}, {} 
  
  def self.compute_shadows(os_model)
    new_groups, @@os2su = SketchUp.get_os2su(os_model, true)
    @@new_group.erase!
    @@new_group = new_groups.first

    @@sub_surface2sunlit_vertices, exterior_surfaces = {}, []
    @@total_floor_area = 0.0
    os_model.getSpaces.each do |space|
      space.surfaces.each do |surface|
        next if surface.name.get.to_s.start_with?("PT ")
        boundary_condition = surface.outsideBoundaryCondition
        next if boundary_condition.eql?("Surface")
        
        exterior_surfaces << surface
        next unless space.partofTotalFloorArea
        next unless boundary_condition.eql?("Outdoors")
        
        @@total_floor_area += Geometry.get_floor_area(space)
        surface.subSurfaces.each do |sub_surface|
          @@sub_surface2sunlit_vertices[sub_surface] = {
            "direct" => @@sun_thetas.length.times.map do Geom2D::PolygonSet.new end,
            "diffuse" => @@phis.length.times.map do @@thetas.length.times.map do Geom2D::PolygonSet.new end end
          }
        end
      end
    end
    exterior_surfaces += os_model.getShadingSurfaces
    @@outdoor_sub_surfaces = @@sub_surface2sunlit_vertices.keys.sort_by do |sub_surface|
      sub_surface.name.get.to_s.split("Sub Surface ").last.to_i
    end
        
    @@coplanar_outdoor_sub_surfaces = {}
    @@outdoor_sub_surfaces.each do |sub_surface|
      sub_surface_plane = sub_surface.space.get.transformation * sub_surface.plane 
      sub_surface_plane = @@coplanar_outdoor_sub_surfaces.keys.find do |plane| plane.equal(sub_surface_plane) end || sub_surface_plane
      plane_hash = @@coplanar_outdoor_sub_surfaces[sub_surface_plane] || { "sub_surfaces" => [], "fronts" => [] }
      plane_hash["sub_surfaces"] << sub_surface
      @@coplanar_outdoor_sub_surfaces[sub_surface_plane] = plane_hash
    end
          
    @@coplanar_outdoor_sub_surfaces.each do |plane, plane_hash|
      normal, d = plane.outwardNormal, plane.d
             
      exterior_surfaces.map do |exterior_surface|
        outdoor_transformation = case
        when !exterior_surface.to_Surface.empty?
          exterior_surface.space
        when !exterior_surface.to_ShadingSurface.empty?
          exterior_surface.shadingSurfaceGroup
        end.get.transformation
        
        outdoor_vertices = outdoor_transformation * exterior_surface.vertices
        face_transformation = OpenStudio::Transformation.alignFace(outdoor_vertices)
        polygon = Geom2D::Polygon.new((face_transformation.inverse * outdoor_vertices).map do |vertex| [vertex.x, vertex.y] end)
        polygon.reverse! unless polygon.ccw?
        outdoor_polygon_set = Geom2D::PolygonSet.new([polygon])
        
        outdoor_plane = outdoor_transformation * exterior_surface.plane
        outdoor_normal, outward_d = outdoor_plane.outwardNormal, outdoor_plane.d
        intersection_vector = outdoor_normal.cross(normal)
        next if Geom2D::Utils.float_compare(intersection_vector.length, 0) < 1 && Geom2D::Utils.float_compare(d, Geom2D::Utils.float_compare(outdoor_normal.dot(normal), 0) > 0 ? outward_d : -outward_d) < 1
        
        plane_hash["fronts"] << if Geom2D::Utils.float_compare(intersection_vector.length, 0) < 1 then 
          outdoor_polygon_set
        else
          axis_normal = [0, 0, 0]
          axis_normal[["x", "y", "z"].find_index do |coordinate| eval("Geom2D::Utils.float_compare(intersection_vector.#{coordinate}, 0) != 0") end] = 1
          eval("axis_normal = OpenStudio::Vector3d.new(#{axis_normal.join(", ")})")
          
          vector_u = normal
          vector_v = outdoor_normal
          vector_w = axis_normal
          detA = vector_u.dot(vector_v.cross(vector_w))
          
          vector_u = OpenStudio::Vector3d.new(-d, normal.y, normal.z)
          vector_v = OpenStudio::Vector3d.new(-outward_d, outdoor_normal.y, outdoor_normal.z)
          vector_w = OpenStudio::Vector3d.new(0, axis_normal.y, axis_normal.z)
          detAu = vector_u.dot(vector_v.cross(vector_w))
          
          vector_u = OpenStudio::Vector3d.new(normal.x, -d, normal.z)
          vector_v = OpenStudio::Vector3d.new(outdoor_normal.x, -outward_d, outdoor_normal.z)
          vector_w = OpenStudio::Vector3d.new(axis_normal.x, 0, axis_normal.z)
          detAv = vector_u.dot(vector_v.cross(vector_w))
          
          vector_u = OpenStudio::Vector3d.new(normal.x, normal.y, -d)
          vector_v = OpenStudio::Vector3d.new(outdoor_normal.x, outdoor_normal.y, -outward_d)
          vector_w = OpenStudio::Vector3d.new(axis_normal.x, axis_normal.y, 0)
          detAw = vector_u.dot(vector_v.cross(vector_w))
          
          intersection_point = OpenStudio::Point3d.new(detAu/detA, detAv/detA, detAw/detA)
          
          start_point = face_transformation.inverse * intersection_point
          end_point = face_transformation.inverse * (intersection_point + intersection_vector)
          interection_segment = Geom2D::Segment.new(Geom2D::Point(start_point.x, start_point.y), Geom2D::Point(end_point.x, end_point.y))

          outdoor_polygon_set.front(interection_segment)
        end.polygons.map do |polygon|
          polygon.to_ary.map do |vertex| face_transformation * OpenStudio::Point3d.new(vertex.x, vertex.y, 0) end
        end
      end
    end
          
    @@phis.each_with_index do |phi, j|
      @@thetas.each_with_index do |theta, i|
        sun_direction = OpenStudio::Vector3d.new(Math.cos(phi)*Math.sin(theta), Math.cos(phi)*Math.cos(theta), Math.sin(phi)).reverseVector
        
        @@coplanar_outdoor_sub_surfaces.each do |plane, plane_hash|            
          next unless Geom2D::Utils.float_compare(plane.outwardNormal.dot(sun_direction), 0) < 0
          
          shadow = self.get_shadow(sun_direction, plane, plane_hash)
          
          sub_surfaces = plane_hash["sub_surfaces"]
          sub_surfaces_transformation = OpenStudio::Transformation.alignFace(sub_surfaces.first.space.get.transformation * sub_surfaces.first.vertices)
          sub_surfaces.each do |sub_surface|
            vertices = sub_surface.space.get.transformation * sub_surface.vertices
            polygon = Geom2D::Polygon.new((sub_surfaces_transformation.inverse * vertices).map do |vertex| [vertex.x, vertex.y] end)
            sub_surface_sunlit = Geom2D::Algorithms::PolygonOperation.run(Geom2D::PolygonSet.new([polygon]), shadow, :difference)
            @@sub_surface2sunlit_vertices[sub_surface]["diffuse"][j][i] = sub_surface_sunlit
            
            next unless j.eql?(@@phis.length - 1)
            
            @@sub_surface2sunlit_vertices[sub_surface]["diffuse"][@@phis.length - 1].length.times do |k|
              next if k.eql?(0)
              @@sub_surface2sunlit_vertices[sub_surface]["diffuse"][@@phis.length - 1][k] = sub_surface_sunlit
            end
          end
        end
        break if j.eql?(@@phis.length - 1)
      end
    end
    
    @@sun_thetas.each_with_index do |sun_theta, k|        
      sun_phi = @@sun_phis[k]
      sun_direction = OpenStudio::Vector3d.new(Math.cos(sun_phi)*Math.sin(sun_theta), Math.cos(sun_phi)*Math.cos(sun_theta), Math.sin(sun_phi)).reverseVector
      
      @@coplanar_outdoor_sub_surfaces.each do |plane, plane_hash|            
        next unless Geom2D::Utils.float_compare(plane.outwardNormal.dot(sun_direction), 0) < 0
        
        shadow = self.get_shadow(sun_direction, plane, plane_hash)
        
        sub_surfaces = plane_hash["sub_surfaces"]
        sub_surfaces_transformation = OpenStudio::Transformation.alignFace(sub_surfaces.first.space.get.transformation * sub_surfaces.first.vertices)
        sub_surfaces.each do |sub_surface|
          vertices = sub_surface.space.get.transformation * sub_surface.vertices
          polygon = Geom2D::Polygon.new((sub_surfaces_transformation.inverse * vertices).map do |vertex| [vertex.x, vertex.y] end)
          sub_surface_sunlit = Geom2D::Algorithms::PolygonOperation.run(Geom2D::PolygonSet.new([polygon]), shadow, :difference)
          @@sub_surface2sunlit_vertices[sub_surface]["direct"][k] = sub_surface_sunlit
        end
      end
    end
        
    script = []
    
    script << "var tbody = document.getElementsByTagName('tbody')[0]"
    script << "$('#table tbody tr').remove()"
    
    @@h_sh_obst_jul_dirs, @@h_sh_obst_jul_difs, @@g_gl_sh_wis = {}, {}, {}
    @@total_phi_sol_jul = 0.0
    @@outdoor_sub_surfaces.each_with_index do |sub_surface, index|
      script << "var row = tbody.insertRow(#{index})"
      script << "var surface_name = row.insertCell(0)"
      script << "surface_name.innerHTML = '#{sub_surface.name.get.to_s}'"
      area = sub_surface.grossArea
      script << "var area = row.insertCell(1)"
      script << "area.innerHTML = parseFloat(#{area}).toFixed(1)"
      h_sol_jul_dir, h_sol_jul_dif = self.get_h_sol_jul(sub_surface, false)
      script << "var h_sol_jul_dir = row.insertCell(2)"
      script << "h_sol_jul_dir.innerHTML = parseFloat(#{h_sol_jul_dir}).toFixed(1)"
      script << "var h_sol_jul_dif = row.insertCell(3)"
      script << "h_sol_jul_dif.innerHTML = parseFloat(#{h_sol_jul_dif}).toFixed(1)"
      h_sh_obst_jul_dir, h_sh_obst_jul_dif = self.get_h_sol_jul(sub_surface, true)
      @@h_sh_obst_jul_dirs[sub_surface] = h_sh_obst_jul_dir
      @@h_sh_obst_jul_difs[sub_surface] = h_sh_obst_jul_dif
      script << "var f_sh_obst_jul_dir = row.insertCell(4)"
      if Geom2D::Utils.float_compare(h_sol_jul_dir, 0) > 0 then
        script << "f_sh_obst_jul_dir.innerHTML = parseFloat(#{h_sh_obst_jul_dir / h_sol_jul_dir}).toFixed(2)"
      else
        script << "f_sh_obst_jul_dir.innerHTML = '-'"
      end
      script << "var f_sh_obst_jul_dif = row.insertCell(5)"
      if Geom2D::Utils.float_compare(h_sol_jul_dir, 0) > 0 then
        script << "f_sh_obst_jul_dif.innerHTML = parseFloat(#{h_sh_obst_jul_dif / h_sol_jul_dif}).toFixed(2)"
      else
        script << "f_sh_obst_jul_dif.innerHTML = '-'"
      end
      g_gl_sh_wi = self.get_g_gl_sh_wi(sub_surface)
      @@g_gl_sh_wis[sub_surface] = g_gl_sh_wi
      script << "var g_gl_sh_wi = row.insertCell(6)"
      script << "g_gl_sh_wi.innerHTML = parseFloat(#{g_gl_sh_wi}).toFixed(2)"
      script << "var phi_sol_jul = row.insertCell(7)"
      phi_sol_jul = (h_sh_obst_jul_dir + h_sh_obst_jul_dif) * area * g_gl_sh_wi
      script << "phi_sol_jul.innerHTML = parseFloat(#{phi_sol_jul}).toFixed(1)"
      
      @@total_phi_sol_jul += phi_sol_jul
    end
    
    if @@total_floor_area > 1e-6 then
      script << "document.getElementById('qsoljul').classList.remove('hide')"
      script << "var q_sol_jul = document.querySelectorAll('#qsoljul input')[0]"
      q_sol_jul = @@total_phi_sol_jul / @@total_floor_area
      script << "q_sol_jul.value = parseFloat(#{q_sol_jul}).toFixed(2)"
      script << "q_sol_jul.style.color = '#{ q_sol_jul > @@q_sol_jul_lim ? "red" : nil }'"
    else
      script << "document.getElementById('qsoljul').classList.add('hide')"
    end
    
    return script
  end
  
  compute_shadows = true
  
  dialog.add_action_callback("compute_shadows") do |action_context|
    script = []
    
    if compute_shadows then
      script += self.compute_shadows(os_model)
      script << "sketchup.set_render('output', null, null);" if @@render.eql?("openstudio")
      compute_shadows = false
    end
    
    dialog.execute_script(script.join(";"))
  end
    
  dialog.add_action_callback("set_render") do |action_context, option, id, li|
    script = []
        
    @@render = option
    if @@render.eql?("openstudio") then
      @@new_group.hidden = true
      os_model.getSpaces.each do |space| space.drawing_interface.entity.hidden = false end
      
      script << "document.getElementById('top').classList.add('hide')"
      script << "document.getElementById('left').classList.add('hide')"
      script << "document.getElementById('main').classList.add('hide')"
      script << "var spans = document.querySelectorAll('#footer_left > span')"
      script << "spans[0].classList.add('hide')"
      script << "spans[1].classList.add('hide')"
      
      compute_shadows = true
      script << "document.getElementById('qsoljul').classList.add('hide')"
      @@total_phi_sol_jul = nil
    else
      @@new_group.hidden = false
      os_model.getSpaces.each do |space| space.drawing_interface.entity.hidden = true end

      script << "document.getElementById('top').classList.remove('hide')"
      script << "document.getElementById('left').classList.remove('hide')"
      script << "document.getElementById('main').classList.remove('hide')"
      script << "var spans = document.querySelectorAll('#footer_left > span')"
      script << "spans[0].classList.remove('hide')"
      script << "spans[1].classList.remove('hide')"
      
      case @@render
      when "input"
        unless id.nil? then
          li_object = case id
          when "glazings"
            os_model.getLayeredConstructionByName(li).get
          when "frames"
            os_model.getWindowPropertyFrameAndDividerByName(li).get
          when "shades"
            os_model.getShadingControlByName(li).get
          end
          
          self.render_by_selection(id, li_object)
        end
        
      when "output"
        if compute_shadows then
          script += self.compute_shadows(os_model)
          compute_shadows = false
        end
        
        self.render_by_phi_sol_jul
      end
    end
        
    dialog.execute_script(script.join(";"))
  end
  
  dialog.add_action_callback("select_sub_surface") do |action_context, sub_surface_name|
    selection = su_model.selection
    selection.clear
    face = @@os2su[os_model.getSubSurfaceByName(sub_surface_name).get]
    selection.add(face)
    face.edges.each do |edge| selection.add(edge) end
  end
  
  dialog.add_action_callback("sort_sub_surfaces") do  |action_context, sub_surface_names|
    @@outdoor_sub_surfaces.sort_by! do |sub_surface|
      sub_surface_names.index(sub_surface.name.get.to_s)
    end
  end
  
  ok = false
  dialog.add_action_callback("ok") do |action_context|
    ok = true
    
    dialog.close
  end
  
  dialog.add_action_callback("cancel") do |action_context|      
    dialog.close
  end
  
  dialog.set_on_closed do
    @@new_group.erase!
    if ok then
      os_model.getSpaces.each do |space| space.drawing_interface.entity.hidden = false end
      if os_path.nil?
        Plugin.command_manager.save_openstudio_as
      else
        Plugin.model_manager.model_interface.export_openstudio(os_path)
      end
    else
      if os_path.nil? then
        Plugin.model_manager.open_openstudio(Plugin.minimal_template_path, su_model, false, false)
      else
        Plugin.model_manager.open_openstudio(os_path, su_model)
      end
    end
  end
    
  dialog.center
  dialog.show
  
end