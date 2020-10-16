
class SketchUp

  def self.is_interior(transformation_su, planar_surface, face)
    planar_surface.drawing_interface.entity.vertices.each do |vertex|
      result = face.classify_point(transformation_su*vertex.position)
      next unless result == Sketchup::Face::PointNotOnPlane || result == Sketchup::Face::PointOutside
      return false
    end

    return true
  end

  def self.get_selected_planar_surfaces(os_model)
    planar_surfaces = []

    Sketchup.active_model.selection.grep(Sketchup::Face).each do |face|
      os_model.getSpaces.each do |space|
        group = space.drawing_interface.entity
        # next if group.hidden?
        transformation_su = group.transformation
        space.surfaces.each do |surface|
          normal = surface.outwardNormal
          next if surface.outsideBoundaryCondition.eql?("Surface") && face.normal.angle_between(transformation_su*Geom::Vector3d.new(normal.x , normal.y, normal.z)) > 1e-6
          planar_surfaces << surface if self.is_interior(transformation_su, surface, face)
          surface.subSurfaces.each do |sub_surface|
            next unless self.is_interior(transformation_su, sub_surface, face)
            planar_surfaces << sub_surface
          end
        end
      end
    end

    return planar_surfaces
  end

  def self.get_os2su(os_model, merge_adjacent)
    new_groups, os2su = [], {}

    if merge_adjacent then
      new_group = Sketchup.active_model.entities.add_group
      new_group.locked = true
      new_groups << new_group
    end

    os_model.getSpaces.each do |space|
      group = space.drawing_interface.entity
      group.hidden = true
      transformation = group.transformation

      unless merge_adjacent then
        new_group = Sketchup.active_model.entities.add_group
        new_group.locked = true
        new_groups << new_group
      end

      space.surfaces.each do |surface|
        next if surface.name.get.to_s.start_with?("PT ")
        next if os2su.include?(surface)
        adjacent_surface = surface.adjacentSurface
        face = new_group.entities.add_face(surface.drawing_interface.entity.outer_loop.vertices.map do |vertex| transformation*vertex.position end)
        os2su[surface] = face
        os2su[adjacent_surface.get] = face if merge_adjacent && !adjacent_surface.empty?
        surface.subSurfaces.each do |sub_surface|
          face = new_group.entities.add_face(sub_surface.drawing_interface.entity.outer_loop.vertices.map do |vertex| transformation*vertex.position end)
          os2su[sub_surface] = face
          os2su[sub_surface.adjacentSubSurface.get] = face if merge_adjacent && !adjacent_surface.empty?
        end
      end
    end

    color = Sketchup::Color.new(255, 255, 255, 1.0)
    os2su.values.uniq.each do |face|
      face.material = color
      face.back_material = color
    end

    return new_groups, os2su
  end

  def self.get_space(group, os2su)
    os2su.each do |planar_surface, face|
      next unless group.entities.include?(face)
      space = planar_surface.space
      next if space.empty?

      return space.get
    end

    return nil
  end

  def self.get_edge_surfaces(edge, groups, su2os)
    start, other_vertex = edge.start.position, edge.end.position
    vertices_a = [OpenStudio::Point3d.new(start.x.to_m, start.y.to_m, start.z.to_m), OpenStudio::Point3d.new(other_vertex.x.to_m, other_vertex.y.to_m, other_vertex.z.to_m)]

    return groups.inject([]) do |sum, group|
      transformation = group.transformation
      sum + group.entities.grep(Sketchup::Edge).map do |edge|
        start, other_vertex = transformation * edge.start.position, transformation * edge.end.position
        vertices_b = [OpenStudio::Point3d.new(start.x.to_m, start.y.to_m, start.z.to_m), OpenStudio::Point3d.new(other_vertex.x.to_m, other_vertex.y.to_m, other_vertex.z.to_m)]
        next unless Geometry.get_length(vertices_a, vertices_b) > 0
        edge.faces[0..1].map do |face| su2os[face] end
      end.compact
    end
  end

  def self.set_material(entity, color)
    return true if !entity.material.nil? && entity.material.color == color
    
    entity.material = color
    entity.back_material = color if entity.is_a?(Sketchup::Face)
    
    return true
  end

end