
class ThermalBridges
  
  @@atlas_cte = JSON.parse(File.read("#{File.dirname(__FILE__)}/CTE/AtlasCTE.json"))

  def self.get_cte_thermal_bridge_types
    return @@atlas_cte.keys
  end

  def self.get_zc_thermal_bridge_types
    return [@@atlas_cte.keys.first] + ["hueco"] + @@atlas_cte.keys[4..-1]
  end
  
  def self.get_ngroups(thermal_bridge_type)
    return 3 if ["hueco", "contorno_de_solera"].include?(thermal_bridge_type)
    
    return 2
  end
  
  def self.interpolate(array, f_array, x)
    aux = [[x, array.first].max, array[-2]].min
    a = array.select do |x| x <= aux end.max
    b = array.select do |x| x > aux end.min
    f_a = f_array[array.index(a)]
    f_b = f_array[array.index(b)]
    
    return f_a+(f_b-f_a)/(b-a)*(x-a)
  end
 
  def self.get_default_psi
    return 0.97
  end
  
  def self.get_cte_psi(thermal_bridge_type, group, u_exterior_wall, other)
    table_hash = @@atlas_cte[thermal_bridge_type][group - 1]
    table, rows = table_hash["table"], table_hash["u_exterior_wall"]
    if table[0].is_a?(Array) then
      f_array = table.map do |row| self.interpolate(table_hash["other"], row, other) end
      return self.interpolate(table_hash["u_exterior_wall"], f_array, u_exterior_wall)
    else
      return self.interpolate(rows, table, 0.5*(u_exterior_wall+other))
    end
    
    return self.get_default_psi
  end 
    
  def self.add_surface(os_model, space_name, thermal_bridge_type, length, psi)
    return true unless psi > 1e-6 
    
    construction_type = thermal_bridge_type.gsub("_"," ")
    construction_name = "PT #{thermal_bridge_type.gsub("_"," ")} zona #{space_name}"
    
    material = OpenStudio::Model::MasslessOpaqueMaterial.new(os_model)
    material.setName(construction_name)
    material.setThermalResistance(1.0 / psi)
    material.setThermalAbsorptance(0.9)
    material.setSolarAbsorptance(0.7)
    material.setVisibleAbsorptance(0.7)
    
    layers = OpenStudio::Model::MaterialVector.new
    layers << material
    construction = OpenStudio::Model::Construction.new(os_model)
    construction.setName(construction_name)
    construction.setLayers(layers)
    
    coordenadaX = {
      "jamba" => 0.5,
      "dintel" => 0.55,
      "alfeizar" => 0.6,
      "capialzado" => 0.65,
      "contorno_de_solera" => 1.0,
      "contorno_cubierta" => 1.75,
      "frente_forjado" => 2.5,
      "forjado_aire" => 2.6,
      "pilares" => 2.75,
      "esquina" =>  2.85
    }[thermal_bridge_type]
    
    new_vertices = []
    new_vertices << OpenStudio::Point3d.new(coordenadaX, 0,-3)
    new_vertices << OpenStudio::Point3d.new(coordenadaX, length,-3)
    new_vertices << OpenStudio::Point3d.new(coordenadaX, length,-2)
    new_vertices << OpenStudio::Point3d.new(coordenadaX,  0,-2)
    
    new_surface = OpenStudio::Model::Surface.new(new_vertices, os_model)
    surface_type = case thermal_bridge_type
    when "jamba", "dintel", "alfeizar", "capialzado"
      thermal_bridge_type.capitalize
      
    when "forjado_aire"
      "forjado"
      
    else
      construction_type
    end
    new_surface.setName("PT #{surface_type} zona #{space_name}")
    new_surface.setSpace(os_model.getSpaceByName(space_name).get)
    new_surface.setSunExposure("NoSun")
    new_surface.setWindExposure("NoWind")
    new_surface.setOutsideBoundaryCondition("Exterior")
    new_surface.setConstruction(construction)
    
    return true
  end

end