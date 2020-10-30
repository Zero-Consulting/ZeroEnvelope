require "#{File.dirname(__FILE__)}/clipper.so"

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
        thickness = Constructions.get_construction_thickness(plane_surface)
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
  
  # Returns the distance from this point to the given point.
  # Geom2D
  def self.distance2D(point_a, point_b)
    return Math.hypot(point_a.first - point_b.first, point_a.last - point_b.last)
  end
  
  def self.clipper(subject, clipping, operation)
    clipper = Clipper::Clipper.new
    
    subject.each do |polygon|
      clipper.add_subject_polygon(polygon.each_vertex.map do |vertex| [vertex.x, vertex.y] end.reverse)
    end
    
    clipping.each do |polygon|
      clipper.add_clip_polygon(polygon.each_vertex.map do |vertex| [vertex.x, vertex.y] end.reverse)
    end
    
    result = []
    case operation
    when :intersection
      clipper.intersection(:even_odd, :even_odd)
    when :union
      clipper.union(:even_odd, :even_odd)
    when :difference
      clipper.difference(:even_odd, :even_odd)
    when :xor
      clipper.xor(:even_odd, :even_odd)
    end.each do |points|
      polygon = []
      result << polygon
      points.each do |point|
        next if polygon.length > 0 && self.distance2D(point, polygon[-1]) < 1e-3
        polygon << point
      end
      polygon.pop if self.distance2D(polygon[0], polygon[-1]) < 1e-3
    end
    
    return result
  end
  
  # Performs the wedge product of this point with the other point.
  # Geom2D
  def self.wedge2D(point_a, point_b)
    other = Geom2D::Point(other)
    
    return point_a.first * point_b.last - point_b.first * point_a.last
  end
  
  # Geom2D
  def self.polygon_area(polygon)
    return 0 if polygon.empty?
    
    area = self..wedge2D(polygon[-1], polygon[0])
    0.upto(polygon.size - 2) {|i| area += self.wedge2D(polygon[i], polygon[i + 1]) }
    
    return area / 2
  end
  
  # Returns +true+ if the vertices of the polygon are ordered in a counterclockwise fashion.
  # Geom2D
  def self.polygon_ccw?(polygon)
    Utilities.float_compare(self.polygon_area(polygon), 0) > -1
  end
  
  # Returns the BoundingBox of this polygon, or an empty BoundingBox if the polygon has no
  # vertices.
  # Geom2D
  def self.polygon_bbox(polygon)
    return [0, 0, 0, 0] if polygon.empty?
    
    vertex = polygon.first
    result = [vertex.first, vertex.last, vertex.first, vertex.last]
    polygon[1..-1].each do |vertex| 
      result = [[result[0], vertex.first].min, [result[1], vertex.last].min, [result[2], vertex.first].max, [result[3], vertex.last].max]
    end
    
    return result
  end
  
  # Returns the BoundingBox of all polygons in the set, or +nil+ if it contains no polygon.
  # Geom2D
  def self.polygons_bbox(polygons)
    return [0, 0, 0, 0] if polygons.empty?
    
    result = self.polygon_bbox(polygons.first)
    polygons[1..-1].each do |polygon|
      polygon_bbox = self.polygon_bbox(polygon)
      result = [[result[0], polygon_bbox[0]].min, [result[1], polygon_bbox[1]].min, [result[2], polygon_bbox[2]].max, [result[3], polygon_bbox[3]].max]
    end
    
    return result
  end
  
  def self.get_front_polygons(polygons, segment)
    front = []

    length = segment.length
    return front if Utilities.float_compare(length, 0) < 1
    
    polygons.each do |polygon|
      px, py = segment.first.first, segment.first.last
      v = [segment.last.first - px, segment.last.last - py]
      dx, dy = v.first.to_f / length, v.last.to_f / length
      d = px*dy - py*dx
      
      distances = []
      each_segment do |polygon_segment|
        distances << polygon_segment.first.first*dy - polygon_segment.first.last*dx - d
      end
      
      polygon_set = [polygon]
      if Utilities.float_compare(distances.min, 0) > -1 then
        front += polygon_set
        next
      end
      distance = distances.max
      next if Utilities.float_compare(distance, 0) < 1
      
      polygons_bbox = self.polygons_bbox(polygons)
      points = case
      when Utilities.float_equal(dx, 0) then [[px, polygons_bbox[1]], [px, polygons_bbox[3]]]
      when Utilities.float_equal(dy, 0) then [[polygons_bbox[0], py], [polygons_bbox[2], py]]
      else
        [(polygons_bbox[0] - px) / dx, (polygons_bbox[2] - px) / dx, (polygons_bbox[1] - py) / dy, (polygons_bbox[3] - py) / dy].sort.values_at(0,-1).map do |t|
          [px + t*dx, py + t*dy]
        end
      end
      bbox_segment = [points.first, points.last]
      bbox_segment.reverse! if Utilities.float_compare(dx * (bbox_segment.last.first - bbox_segment.first.first), 0) < 0
      
      clipping = [
        [bbox_segment.first.first, bbox_segment.first.last],
        [bbox_segment.last.first, bbox_segment.last.last],
        [bbox_segment.last.first + dy*distance, bbox_segment.last.last - dx*distance],
        [bbox_segment.first.first + dy*distance, bbox_segment.first.last - dx*distance]
      ]

      front += Geometry.clipper(polygon_set, [clipping], :intersection)
    end
    
    return front
  end

end