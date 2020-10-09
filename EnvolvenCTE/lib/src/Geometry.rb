
class Geometry
      
  # https://www.lucidarme.me/intersection-of-segments/
  def self.get_length(vertices_a, vertices_b)
    length = 0.0
    
    vertices_a.each_with_index do |vertex_a, index_a|
      prev_a = vertices_a[index_a-1]
      vertices_b.each_with_index do |vertex_b, index_b|
        prev_b = vertices_b[index_b-1]
        
        p1 = prev_a
        p2 = vertex_a
        p3 = prev_b
        p4 = vertex_b
        
        p12 = p2-p1
        p34 = p4-p3
        
        next unless p12.cross(p34).length < 1e-6
        
        p13 = p3-p1
        
        next unless p12.cross(p13).length < 1e-6
        
        p14 = p4-p1
        
        k2 = p12.dot(p12)
        k3 = p12.dot(p13)
        k4 = p12.dot(p14)
                
        table = [
          [0.0, p14.length, p12.length],
          [p13.length, p34.length, (p3-p2).length],
          [p12.length, (p4-p2).length, 0.0]
        ]
        
        row = if k3 < 1e-6 then
          0
        elsif k3 < k2 then
          1
        else
          2
        end
        
        col = if k4 < 1e-6 then
          0
        elsif k4 < k2 then
          1
        else
          2
        end
        
        length += table[row][col]
      end
    end
    length /= 2 if vertices_a.length.eql?(2)
    length /= 2 if vertices_b.length.eql?(2)
    
    return length
  end
  
  def self.contains?(point, vertices)
    vertices.each_with_index do |vertex, i|
      vector_a = point - vertex
      prev_vertex = vertices[i-1]
      vector_b = prev_vertex - vertex
      next if vector_b.cross(vector_a).length > 1e-6
      dot = vector_b.dot(vector_a)
      next if dot < -1e-6
      next if dot > vector_b.length**2
      return true
    end
    
    return false
  end
  
  def self.get_planes_hash(space)
    surfaces = space.surfaces
    
    surfaces_neighbours = surfaces.map do |space_surface|          
      surface_neighbours = surfaces.map do |surface_neighbour|
        next if surface_neighbour.eql?(space_surface)
        next if self.get_length(space_surface.vertices, surface_neighbour.vertices) < 1e-6
        next unless space_surface.plane.equal(surface_neighbour.plane)
        surface_neighbour
      end.compact
      
      [space_surface, surface_neighbours]
    end.to_h

    return Utilities.merge(surfaces_neighbours).map do |plane_surfaces|
      thickness_times_area, total_area = 0.0, 0.0
      plane_surfaces.each do |plane_surface|
        thickness = self.get_construction_thickness(plane_surface)
        case plane_surface.outsideBoundaryCondition
        when "Outdoors", "Ground", "OtherSideCoefficients"
        when "Surface", "Adiabatic"
          thickness /= 2
        else
          next
        end
        
        area = plane_surface.grossArea
        thickness_times_area += thickness*area
        total_area += area
      end
      
      [plane_surfaces, total_area > 1e-6 ? thickness_times_area / total_area : 0.0]
    end.to_h
  end
  
  def self.get_adjacent_surface_properties(edge, planes_hash)
    planes_hash.each do |plane_surfaces, thickness|
      plane_surfaces.each do |surface|
        vertices = surface.vertices
        vertices.each_with_index do |vertex, index|
          next unless self.contains?(edge.first, [vertex, vertices[(index+1) % vertices.length]])
          next unless self.get_length(edge, [vertex, vertices[(index+1) % vertices.length]]) > 1e-6
          return thickness, surface.outwardNormal
        end
      end
    end
    
    return 0.0, nil
  end
            
  def self.get_offset_vertices(surface, planes_hash = nil)
    space = surface.space
    return [] if space.empty?
    
    thickness_k, normal_k = 0.0, surface.outwardNormal
    planes_hash = (planes_hash || self.get_planes_hash(space.get)).map do |plane_surfaces, thickness|
      if plane_surfaces.include?(surface) then
        thickness_k = thickness
        next
      end
      [plane_surfaces, thickness]
    end.compact.to_h
    
    vertices = surface.vertices
    return vertices.each_with_index.map do |vertex, index|
      edge_i, edge_j = [vertex, vertices[(index+1) % vertices.length]], [vertex, vertices[index-1]]
      
      thickness_i, normal_i = self.get_adjacent_surface_properties(edge_i, planes_hash)
      normal_i = normal_i || (edge_i.last - edge_i.first).cross(normal_k)
      
      thickness_j, normal_j = self.get_adjacent_surface_properties(edge_j, planes_hash)
      normal_j = normal_j || (edge_j.last - edge_j.first).cross(normal_k)                
      
      normal_u = normal_i
      normal_v = normal_j
      normal_w = normal_k
      detA = normal_u.dot(normal_v.cross(normal_w))
      
      normal_u = OpenStudio::Vector3d.new(-thickness_i, normal_i.y, normal_i.z)
      normal_v = OpenStudio::Vector3d.new(-thickness_j, normal_j.y, normal_j.z)
      normal_w = OpenStudio::Vector3d.new(-thickness_k, normal_k.y, normal_k.z)
      detAu = normal_u.dot(normal_v.cross(normal_w))
      
      normal_u = OpenStudio::Vector3d.new(normal_i.x, -thickness_i, normal_i.z)
      normal_v = OpenStudio::Vector3d.new(normal_j.x, -thickness_j, normal_j.z)
      normal_w = OpenStudio::Vector3d.new(normal_k.x, -thickness_k, normal_k.z)
      detAv = normal_u.dot(normal_v.cross(normal_w))
      
      normal_u = OpenStudio::Vector3d.new(normal_i.x, normal_i.y, -thickness_i)
      normal_v = OpenStudio::Vector3d.new(normal_j.x, normal_j.y, -thickness_j)
      normal_w = OpenStudio::Vector3d.new(normal_k.x, normal_k.y, -thickness_k)
      detAw = normal_u.dot(normal_v.cross(normal_w))
                
      vertex + OpenStudio::Vector3d.new(detAu/detA, detAv/detA, detAw/detA)
    end
  end
            
  def self.get_offset_area(surface, planes_hash = nil)
    space = surface.space
    return surface.grossArea if space.empty?
    
    coordinates, normal = ["x", "y", "z"], surface.outwardNormal
    max_normal, max_coordinate = coordinates.map do |coordinate|
      eval("[normal.#{coordinate}.abs, coordinate]")
    end.sort.max
    plane_coordinates = coordinates - [max_coordinate]
    
    vertices = self.get_offset_vertices(surface, planes_hash || self.get_planes_hash(space.get))
    area = vertices.each_with_index.map do |vertex, index|
      eval("vertex.#{plane_coordinates.first} * (vertices[(index+1) % vertices.length].#{plane_coordinates.last}-vertices[index-1].#{plane_coordinates.last})")
    end.inject(0.0) do |sum, x| sum + x end.abs / max_normal / 2
      
    return area.round(1)
  end
      
  def self.get_offset_floor_air_area(space, include_air_wall = false, planes_hash = nil)
    planes_hash = planes_hash || self.get_planes_hash(space)
    
    offset_floor_air_area =  space.surfaces.map do |surface|
      next unless surface.surfaceType.eql?("Floor")
      next if !include_air_wall && surface.isAirWall
      self.get_offset_area(surface, planes_hash)
    end.compact.inject(0.0) do |sum, x| sum + x end.round(1)
    
    return offset_floor_air_area
  end
      
  def self.get_offset_air_area(space, planes_hash = nil)
    offset_air_area = space.additionalProperties.getFeatureAsDouble("offset_air_area")
    return offset_air_area.get unless offset_air_area.empty?
    
    offset_air_area = self.get_offset_floor_air_area(space, true, planes_hash || self.get_planes_hash(space))
    space.additionalProperties.setFeature("offset_air_area", offset_air_area)
    
    return offset_air_area
  end
      
  def self.get_offset_floor_area(space, planes_hash = nil)
    offset_floor_area = space.additionalProperties.getFeatureAsDouble("offset_floor_area")
    return offset_floor_area.get unless offset_floor_area.empty?
    
    offset_floor_area = self.get_offset_floor_air_area(space, false, planes_hash || self.get_planes_hash(space))
    space.additionalProperties.setFeature("offset_floor_area", offset_floor_area)
    
    return offset_floor_area
  end
      
  def self.get_floor_area(space, planes_hash = nil)
    floor_area = space.additionalProperties.getFeatureAsDouble("floor_area")
    return floor_area.get unless floor_area.empty?
    
    offset_floor_area = space.additionalProperties.getFeatureAsDouble("offset_floor_area")
    return offset_floor_area.get unless offset_floor_area.empty?
    
    offset_floor_area = self.get_offset_floor_area(space, planes_hash || self.get_planes_hash(space))
    
    return offset_floor_area
  end
      
  def self.get_offset_volume(space, planes_hash = nil)
    planes_hash = planes_hash || self.get_planes_hash(space)
    
    volume = planes_hash.map do |plane_surfaces, thickness|
      plane_surfaces.map do |surface| self.get_offset_area(surface, planes_hash) end.inject(0.0) do |sum, x| sum + x end * (plane_surfaces.first.plane.d + thickness)
    end.inject(0.0) do |sum, x| sum + x end.abs / 3
    
    return volume.round(1)
  end
      
  def self.get_volume(space, planes_hash = nil)
    volume = space.additionalProperties.getFeatureAsDouble("volume")
    return volume.get unless volume.empty?
    
    volume = self.get_offset_volume(space, planes_hash)
    space.additionalProperties.setFeature("volume", volume)
    
    return volume
  end
      
  def self.get_ceiling_height(space, planes_hash = nil)
    ceiling_height = space.additionalProperties.getFeatureAsDouble("ceiling_height")
    return ceiling_height.get unless ceiling_height.empty?
    
    volume = self.get_offset_volume(space, planes_hash)
    floor_area = self.get_floor_area(space, planes_hash)
    return (volume / floor_area).round(1)
  end
 
end