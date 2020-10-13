
class Constructions

  def self.set_air_gap_thickness(air_gap, thickness)
    air_gap.additionalProperties.setFeature("thickness", thickness)
    thermal_resistance = thickness < 1e-6 ? 0.0 : 1/([0.025/thickness, 1.25].max+5.1/(2/0.9-1))

    return air_gap.to_OpaqueMaterial.get.to_AirGap.get.setThermalResistance(thermal_resistance)
  end

  def self.set_thickness(material, thickness)
    eq_air_gap = if material.to_AirGap.empty? then
      material.setThickness(thickness)
      material.additionalProperties.getFeatureAsDouble("mu").get*thickness
    else
      self.set_air_gap_thickness(material, thickness)
      0.01
    end

    return material.additionalProperties.setFeature("eq_air_gap", eq_air_gap)
  end
    
  def self.add_interface_objects(os_model, os_type)
    script = []
    
    objects = nil
    os_type.each do |id, type|
      script << "var ul = document.querySelectorAll('##{id} > ul')[0]"
      eval("objects = os_model.get#{type}s")
      objects.sort_by do |object|
        object.name.get.to_s
      end.select do |object|
        interface = object.additionalProperties.getFeatureAsBoolean("interface")
        !interface.empty? && interface.get
      end.each do |object|
        script << "var li = document.createElement('li')"
        script << "li.appendChild(document.createTextNode('#{object.name.get.to_s}'))"
        script << "ul.appendChild(li)"
      end
    end

    return script
  end

  def self.get_reversed_type(os_model, construction)
    reversed = construction.additionalProperties.getFeatureAsBoolean("reversed")
    return 3 if !reversed.empty? && reversed.get # reversed
    
    reversed_construction = self.get_reversed_construction(os_model, construction)
    return 0 unless reversed_construction # cannot be reversed
    
    reversed = reversed_construction.additionalProperties.getFeatureAsBoolean("reversed")
    return 2 if !reversed.empty? && reversed.get # mirror

    reversed_construction.remove      
    return 1 # can be reversed
  end

  def self.reverseConstructionWithInternalSource(os_model, construction)
    reversed_layers = construction.layers.reverse
    num_layers = construction.numLayers
    source_layer = construction.sourcePresentAfterLayerNumber
    temperature_layer = construction.temperatureCalculationRequestedAfterLayerNumber
    ctf_dimensions = construction.dimensionsForTheCTFCalculation
    tube_spacing = construction.tubeSpacing
    
    os_model.getConstructionWithInternalSources.each do |reversed_construction|
      next unless reversed_layers.eql?(reversed_construction.layers)
      next unless source_layer.eql?(num_layers-reversed_construction.sourcePresentAfterLayerNumber)
      next unless temperature_layer.eql?(num_layers-reversed_construction.temperatureCalculationRequestedAfterLayerNumber)
      next unless ctf_dimensions.eql?(reversed_construction.dimensionsForTheCTFCalculation)
      next unless tube_spacing.eql?(reversed_construction.tubeSpacing)
      return reversed_construction
    end
    
    reversed_construction = OpenStudio::Model::ConstructionWithInternalSource.new(os_model)
    reversed_construction.setName("#{construction.name.get.to_s} Reversed")
    reversed_construction.additionalProperties.setFeature("interface", true)
    reversed_construction.setLayers(reversed_layers)
    reversed_construction.setSourcePresentAfterLayerNumber(num_layers-construction.sourcePresentAfterLayerNumber)
    reversed_construction.setTemperatureCalculationRequestedAfterLayerNumber(num_layers-construction.temperatureCalculationRequestedAfterLayerNumber)
    reversed_construction.setDimensionsForTheCTFCalculation(ctf_dimensions)
    reversed_construction.setTubeSpacing(tube_spacing)
    return reversed_construction
  end

  def self.get_reversed_construction(os_model, construction_base)
    construction = construction_base.to_Construction
    unless construction.empty? then
      construction = construction.get
      return false if construction.isSymmetric
      return construction.reverseConstruction
    end
    
    construction_with_internal_source = construction_base.to_ConstructionWithInternalSource
    unless construction_with_internal_source.empty? then
      construction_with_internal_source = construction_with_internal_source.get
      reversed_construction = self.reverseConstructionWithInternalSource(os_model, construction_with_internal_source)
      return false if reversed_construction.eql?(construction_with_internal_source)
      return reversed_construction
    end
    
    return false
  end

  def self.get_layer_thickness(material)
    thickness = material.additionalProperties.getFeatureAsDouble("thickness")
    return thickness.get unless thickness.empty? || material.to_AirGap.empty?

    return material.thickness
  end

  def self.get_opaque_materials(os_model, material_name)
    return os_model.getOpaqueMaterials.select do |opaque_material|
      material = opaque_material.additionalProperties.getFeatureAsString("material")
      !material.empty? && material.get.eql?(material_name)
    end
  end

  def self.add_default_construction(os_model, object_name, id, construction_set)
    object_name = Utilities.fix_name(object_name)
    simple_glazing = os_model.getSimpleGlazingByName(object_name)
    construction = if simple_glazing.empty? then
      os_model.getLayeredConstructionByName(object_name).get
    else
      simple_glazing = simple_glazing.get
      os_model.getConstructions.find do |temp|
        temp.isFenestration && temp.getLayerIndices(simple_glazing).length > 0
      end
    end   
    
    default_constructions_id, default_construction_id = id.split("_surface_")
    if default_construction_id.nil? then
      default_construction_id = id.split("other_")[1]
      eval("construction_set.set#{Utilities.capitalize_all(default_construction_id)}Construction(construction)")
    else
      default_constructions_id += "_surface"
      surface_type = ["roof", "ceiling"].include?(default_construction_id) ? "roof_ceiling" : default_construction_id
      "construction_set.default#{Utilities.capitalize_all(default_constructions_id)}Constructions.get.set#{Utilities.capitalize_all(surface_type)}Construction(construction)"
      eval("construction_set.default#{Utilities.capitalize_all(default_constructions_id)}Constructions.get.set#{Utilities.capitalize_all(surface_type)}Construction(construction)")
    end
  end

  def self.remove_default_construction(os_model, id, construction_set)
    default_constructions_id, default_construction_id = id.split("_surface_")

    if default_construction_id.nil? then
      default_construction_id = id.split("other_")[1]
      eval("construction_set.reset#{Utilities.capitalize_all(default_construction_id)}Construction")
    else
      default_constructions_id += "_surface"
      surface_type = ["roof", "ceiling"].include?(default_construction_id) ? "roof_ceiling" : default_construction_id
      eval("construction_set.default#{Utilities.capitalize_all(default_constructions_id)}Constructions.get.reset#{Utilities.capitalize_all(surface_type)}Construction")
    end
  end

  def self.divide_materials_interface(os_model, material_name)
    return self.get_opaque_materials(os_model, material_name).partition do |material|
      interface = material.additionalProperties.getFeatureAsBoolean("interface")
      !interface.empty? && interface.get
    end
  end

  def self.get_material(os_model, material_name, thickness = nil)
    material_name = Utilities.fix_name(material_name)
    interface_materials, other_materials = self.divide_materials_interface(os_model, material_name)
    interface_material = interface_materials.first

    thickness = thickness || self.get_layer_thickness(interface_material)
    material = other_materials.find do |material| (self.get_layer_thickness(material) - thickness).abs < 1e-6 end
    if material.nil? then
      material = interface_material.clone(os_model).to_OpaqueMaterial.get
      self.set_thickness(material, thickness)
    end
    material.additionalProperties.setFeature("interface", false)

    return material
  end
  
  def self.get_num_materials(os_model, material)
    num_materials = 0

    os_model.getLayeredConstructions.each do |layered_construction|
      reversed = layered_construction.additionalProperties.getFeatureAsBoolean("reversed")
      next if !reversed.empty? && reversed.get
      num_materials += layered_construction.getLayerIndices(material).length

      edge_insulation = os_model.getFoundationKivaByName(Utilities.fix_name(layered_construction.name.get.to_s))
      next if edge_insulation.empty?
      edge_insulation = edge_insulation.get

      insulation_material = nil
      [["interior", "horizontal", "width"], ["exterior", "vertical", "depth"]].each do |type|
        eval("insulation_material = edge_insulation.#{type[0]}#{type[1].capitalize}InsulationMaterial")
        next unless !insulation_material.empty? && insulation_material.get.eql?(material)
        num_materials += 1
      end
    end

    return num_materials
  end

  def self.get_glazing_u_factor(sub_surface)
    construction = sub_surface.construction
    return 1e6 if construction.empty?
    
    construction = construction.get
    while true do
      layers = construction.to_LayeredConstruction.get.layers
      break unless layers.length.eql?(1)
      
      simple_glazing = layers.first.to_SimpleGlazing
      break if simple_glazing.empty?
      
      return simple_glazing.get.uFactor
    end

    return 1e6
  end

  def self.get_frame_perimeter(sub_surface)
    vertices = sub_surface.vertices

    return Geometry.get_length(vertices, vertices)
  end

  def self.get_frame_area(sub_surface, perimeter, width)
    return ((perimeter || self.get_frame_perimeter(sub_surface)) + 4 * width) * width
  end

  def self.get_R_si(planar_surface)
    surface = planar_surface.to_Surface
    surface = planar_surface.to_SubSurface.get.surface if surface.empty?

    return case surface.get.surfaceType
    when "Floor"
      0.17
    when "Wall"
      0.13
    when "RoofCeiling"
      0.1
    end

    return 0.0
  end

  def self.get_R_se
    return 0.04
  end

  def self.get_outdoors_window_thermal_properties(sub_surface)
    sub_surface_area = sub_surface.grossArea
    sub_surface_u_factor = self.get_glazing_u_factor(sub_surface)
    frame = sub_surface.windowPropertyFrameAndDivider
    return sub_surface_area, sub_surface_u_factor if frame.empty?

    frame = frame.get
    frame_conductance = frame.frameConductance
    perimeter = self.get_frame_perimeter(sub_surface)
    frame_area = self.get_frame_area(sub_surface, perimeter, frame.frameWidth)
    return sub_surface_area, sub_surface_u_factor, frame_area, 1e6, perimeter, 1e6 if frame_conductance.empty?

    frame_conductance = frame_conductance.get
    frame_u_factor = 1.0 / (self.get_R_si(sub_surface) + 1.0 / frame_conductance + self.get_R_se)
    frame_type = [frame_conductance, 1.5, 4.4].sort.index(frame_conductance)
    glazing_type = [sub_surface_u_factor, 1.8, 3.5].sort.reverse.index(sub_surface_u_factor)
    psi_value = [[0.0, 0.5, 0.6], [0.0, 0.06, 0.08], [0.0, 0.01, 0.04]][frame_type][glazing_type]
    
    return sub_surface_area, sub_surface_u_factor, frame_area, frame_u_factor, perimeter, psi_value
  end

  def self.get_opaque_u_factor(r_si, surface, r_se)
    construction = surface.construction
    return 1e6 if construction.empty?
    
    return 1.0 / (r_si + 1.0 / construction.get.thermalConductance.get + r_se)
  end

  def self.get_outdoors_u_factor(planar_surface)
    sub_surface = planar_surface.to_SubSurface
    return self.get_glazing_u_factor(sub_surface.get) unless sub_surface.empty?

    surface = planar_surface.to_Surface.get
    r_si, r_se = self.get_R_si(surface), self.get_R_se
    
    return self.get_opaque_u_factor(r_si, surface, r_se)
  end

  def self.get_surface_u_factor(planar_surface)
    sub_surface = planar_surface.to_SubSurface
    return self.get_glazing_u_factor(sub_surface.get) unless sub_surface.empty?

    surface = planar_surface.to_Surface.get
    r_si = self.get_R_si(surface)

    return self.get_opaque_u_factor(r_si, surface, r_si)
  end

  def self.get_unconditioned_u_factor(planar_surface, adjacent_space)
    au = 0.33 * Geometry.get_volume(adjacent_space) * adjacent_space.infiltrationDesignAirChangesPerHour

    adjacent_space.surfaces.each do |surface|
      next unless surface.outsideBoundaryCondition.eql?("Outdoors")
      surface_area = surface.netArea

      surface.subSurfaces.each do |sub_surface|
        sub_surface_area, u_factor, frame_area, frame_u_factor, perimeter, psi_value = self.get_outdoors_window_thermal_properties(sub_surface)
        au += sub_surface_area * u_factor
        
        unless frame_area.nil? then
          surface_area -= frame_area
          au += frame_area * frame_u_factor + perimeter * psi_value
        end
      end

      au += self.get_outdoors_u_factor(surface) * surface_area
    end
    return 0.0 if au < 1e-6

    return 1.0 / (1.0 / self.get_surface_u_factor(planar_surface) + planar_surface.netArea / au)
  end

  def self.get_construction_thickness(surface)
    construction = surface.construction
    return 0.0 if construction.empty?
    construction = construction.get.to_LayeredConstruction
    return 0.0 if construction.empty?

    return construction.get.layers.inject(0.0) do |sum, layer| sum + self.get_layer_thickness(layer) end
  end

  def self.get_ground_u_factor(surface, space, ground_level_plane, os_model)
    centroid = space.transformation * surface.centroid
    z = [((-ground_level_plane.d - ground_level_plane.a * centroid.x - ground_level_plane.b * centroid.y) / ground_level_plane.c - centroid.z), 0.0].max
    
    lambda_g = 2.0 # W/m K ISO 13370 default
    r_si, r_se = self.get_R_si(surface), self.get_R_se

    surface_type = surface.surfaceType
    u_factor = case surface_type
    when "Floor", "Wall"
      outdoors_perimeter, unconditioned_perimeter, wall_thickness_times_outdoors_perimeter = 0.0, 0.0, 0.0

      space.surfaces.each do |other|
        next unless other.surfaceType.eql?("Wall")
        length = Geometry.get_length(surface.vertices, other.vertices)
        next if length < 1e-6

        case other.outsideBoundaryCondition
        when "Outdoors"
          outdoors_perimeter += length
          wall_thickness_times_outdoors_perimeter += self.get_construction_thickness(other) * length
          
        when "Surface"
          unconditioned_perimeter += length unless other.adjacentSurface.get.space.get.partofTotalFloorArea
        end
      end

      perimeter = [outdoors_perimeter + unconditioned_perimeter, 1e-6].max
      d_w_e = outdoors_perimeter > 1e-6 ? wall_thickness_times_outdoors_perimeter / outdoors_perimeter : 0.0
      
      d_g = lambda_g / self.get_opaque_u_factor(r_si, surface, r_se)
      d_f = d_w_e + d_g

      case surface_type
      when "Floor"
        b = surface.grossArea / (0.5 * perimeter)
        
        u_factor_0 = if d_f + 0.5 * z < b then
          2 * lambda_g / (Math::PI * b + d_f + 0.5 * z) * Math.log(Math::PI * b / (d_f + 0.5 * z) + 1)
        else
          lambda_g / (0.457 * b + d_f + 0.5 * z)
        end
        
        while true do
          construction = surface.construction
          break if construction.empty?
          
          edge_insulation = os_model.getFoundationKivaByName(construction.get.name.get.to_s)
          break if edge_insulation.empty?

          edge_insulation, insulation_material, d = edge_insulation.get, nil, nil
          [["interior", "horizontal", "width", 1], ["exterior", "vertical", "depth", 2]].each do |interior_exterior, horizontal_vertical, width_depth, coeff|
            eval("insulation_material = edge_insulation.#{interior_exterior}#{horizontal_vertical.capitalize}InsulationMaterial")
            next if insulation_material.empty?
            
            insulation_material = insulation_material.get
            d_n, lambda_n = self.get_layer_thickness(insulation_material), insulation_material.to_OpaqueMaterial.get.thermalConductivity
            d_prime = d_n / lambda_n * (lambda_g - lambda_n)
            r_prime = d_prime / lambda_g
            eval("d = edge_insulation.#{interior_exterior}#{horizontal_vertical.capitalize}Insulation#{width_depth.capitalize}")
            next if d.empty?
            
            d = d.get
            u_factor_0 -= 2 * (lambda_g / Math::PI * (Math::log(coeff * d / d_f + 1) - Math::log(coeff * d / (d_f + d_prime) + 1))) / b
          end
          
          break
        end
        
        u_factor_0

      when "Wall"
        d_w = d_g

        2 * lambda_g / Math::PI / z * (1 + 0.5 * d_f / (d_f + z)) * Math.log(z / d_w + 1)
      end

    when "RoofCeiling"
      1.0 / (r_si + z / lambda_g + r_se)
    end

    return u_factor
  end
  
  def self.get_input_psi(thermal_bridge_type, exterior_wall, other)
    os_model.getMasslessOpaqueMaterials.each do |thermal_bridge|
      type = thermal_bridge.additionalProperties.getFeatureAsString("thermal_bridge_type")
      next if type.empty?
      next unless type.get.eql?(thermal_bridge_type)

      exterior_wall2others = thermal_bridge.additionalProperties.getFeatureAsString("exterior_wall2others")
      next if exterior_wall2others.empty?
      next unless JSON.parse(exterior_wall2others.get)[exterior_wall].include?(other)
      
      return 1.0 / thermal_bridge.thermalResistance 
    end
    
    return ThermalBridges.get_default_psi
  end
  
end