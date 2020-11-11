require "#{File.dirname(__FILE__)}/src/ThermalBridges"
require "json"

module OpenStudio

  su_model = Sketchup.active_model
  os_model = Plugin.model_manager.model_interface.openstudio_model
  os_path = Plugin.model_manager.model_interface.openstudio_path

  # sg save data

  zonaClimatica = os_model.getClimateZones.getClimateZone("CTE", 0).value

  residencialOTerciario = nil
  while true do
    standards_building_type = os_model.building.get.standardsBuildingType()
    break if standards_building_type.empty?

    aux = standards_building_type.get.split("-").map do |x| x.strip() end
    break unless aux.length.eql?(3)

    residencialOTerciario = aux[1]
    break
  end

  if zonaClimatica.empty? || residencialOTerciario.nil? then
    load(File.dirname(__FILE__)+"/CaracteristicasEdificio.rb")

    os_model = Plugin.model_manager.model_interface.openstudio_model
    zonaClimatica = os_model.getClimateZones.getClimateZone("CTE", 0).value
    residencialOTerciario = (os_model.building.get.standardsBuildingType().get.split("-").map do |x| x.strip() end)[1]
  end

  # remove air gaps

  os_model.getAirGaps.each do |air_gap|
    interface = air_gap.additionalProperties.getFeatureAsBoolean("interface")
    next if interface.empty?
    next unless interface.get

    air_gap.remove
  end

  # add air gap

  air_gap = OpenStudio::Model::AirGap.new(os_model, 0.18)
  air_gap_name = "Camara de aire sin ventilar"
  air_gap.setName(air_gap_name)
  air_gap.additionalProperties.setFeature("material", air_gap_name)
  air_gap.additionalProperties.setFeature("interface", true)
  air_gap.additionalProperties.setFeature("editable", true)
  Constructions.set_thickness(air_gap, 0.02)

  # remove thermal bridges

  edges = []
  os_model.getSurfaces.each do |surface|
    next unless surface.name.get.to_s.start_with?("PT ")

    construction = surface.construction.get.to_LayeredConstruction.get
    construction.layers.each do |layer| layer.remove end
    construction.remove
    surface.drawing_interface.entity.edges.each do |edge| edges << edge end
    surface.remove
  end
  edges.each do |edge| edge.erase! unless edge.deleted? end

  # clean thermal bridges

  os_model.getSurfaces.each do |exterior_wall|
    thermal_bridges = exterior_wall.additionalProperties.getFeatureAsString("thermal_bridges")
    next if thermal_bridges.empty?
    (exterior_wall.additionalProperties.resetFeature("thermal_bridges"); next) unless exterior_wall.outsideBoundaryCondition.eql?("Outdoors")
    (exterior_wall.additionalProperties.resetFeature("thermal_bridges"); next) unless exterior_wall.space.get.partofTotalFloorArea

    thermal_bridges = JSON.parse(thermal_bridges.get).map do |thermal_bridge_type, value|
      value = value.each_with_index.map do |others, index|
        others.map do |other_name|
          planar_surface = os_model.getPlanarSurfaceByName(other_name)
          next if planar_surface.empty?
          planar_surface = planar_surface.get

          case thermal_bridge_type
          when "hueco", "capialzado"
            other = planar_surface.to_SubSurface
            next if other.empty?
            next unless exterior_wall.subSurfaces.include?(other.get)

          else
            other = planar_surface.to_Surface.get
            next unless Geometry.get_length(exterior_wall.vertices, other.vertices) > 1e-6

            surface_type, outsise_boundary_condition = other.surfaceType, other.outsideBoundaryCondition
            case thermal_bridge_type
            when "pilares", "esquina"
              next unless surface_type.eql?("Wall") && outsise_boundary_condition.eql?("Outdoors")

              aux = exterior_wall.outwardNormal.dot(other.centroid - exterior_wall.centroid)
              case thermal_bridge_type
              when "pilares"
                next unless aux.abs < 1e-6

              when "esquina"
                case index
                when 0, 2
                  next unless aux < 1e-6

                when 1
                  next unless aux > 1e-6
                end
              end

            when "frente_forjado"
              next unless surface_type.eql?("Floor") && outsise_boundary_condition.eql?("Surface")

            when "contorno_cubierta"
              next unless surface_type.eql?("RoofCeiling") && outsise_boundary_condition.eql?("Outdoors")

            when "forjado_aire"
              next unless surface_type.eql?("Floor") && outsise_boundary_condition.eql?("Outdoors")

            when "contorno_de_solera"
              next unless surface_type.eql?("Floor") && outsise_boundary_condition.eql?("Ground")
            end
          end

          next if index.eql?(0) && os_model.getMasslessOpaqueMaterials.find do |thermal_bridge|
            aux = thermal_bridge.additionalProperties.getFeatureAsString("thermal_bridge_type")
            next if aux.empty?
            next unless aux.get.eql?(thermal_bridge_type)
            exterior_wall2others = thermal_bridge.additionalProperties.getFeatureAsString("exterior_wall2others")
            next if exterior_wall2others.empty?

            JSON.parse(exterior_wall2others.get)[exterior_wall.name.get.to_s].include?(other_name)
          end.nil?

          other_name
        end.compact
      end

      [thermal_bridge_type, value]
    end.to_h

    if thermal_bridges.find do |thermal_bridge_type, value| !value.find do |others| !others.empty? end.nil? end.nil? then
      exterior_wall.additionalProperties.resetFeature("thermal_bridges")
    else
      exterior_wall.additionalProperties.setFeature("thermal_bridges", thermal_bridges.to_json)
    end
  end

  os_model.getMasslessOpaqueMaterials.each do |thermal_bridge|
    thermal_bridge_type = thermal_bridge.additionalProperties.getFeatureAsString("thermal_bridge_type")
    next if thermal_bridge_type.empty?
    thermal_bridge_type = thermal_bridge_type.get
    exterior_wall2others = thermal_bridge.additionalProperties.getFeatureAsString("exterior_wall2others")
    next if exterior_wall2others.empty?

    exterior_wall2others = JSON.parse(exterior_wall2others.get)
    exterior_wall2others = exterior_wall2others.map do |exterior_wall_name, others|
      exterior_wall = os_model.getSurfaceByName(exterior_wall_name)
      next if exterior_wall.empty?

      thermal_bridges = exterior_wall.get.additionalProperties.getFeatureAsString("thermal_bridges")
      next if thermal_bridges.empty?

      others = others.select do |other_name| JSON.parse(thermal_bridges.get)[thermal_bridge_type][0].include?(other_name) end
      next if others.nil?

      [exterior_wall_name, others]
    end.compact.to_h

    thermal_bridge.additionalProperties.setFeature("exterior_wall2others", exterior_wall2others.to_json)
  end

  # get ground level

  ground_surfaces = os_model.getSurfaces.select do |surface| surface.outsideBoundaryCondition.eql?("Ground") end
  ground_level_vertices = []
  ground_surfaces.each do |ground_surface|
    vertices = ground_surface.space.get.transformation * ground_surface.vertices
    vertices.each_with_index do |vertex, i|
      prev_vertex = vertices[i-1]
      vector = vertex - prev_vertex
      vector.setLength(vector.length / 2)
      midpoint = prev_vertex + vector
      isGroundLevel = true
      (ground_surfaces - [ground_surface]).each do |other_surface|
        other_vertices = other_surface.space.get.transformation * other_surface.vertices
        other_vertices.each_with_index do |vertex, i|
          vector_a = midpoint - vertex
          prev_vertex = other_vertices[i-1]
          vector_b = prev_vertex - vertex
          next if vector_b.cross(vector_a).length > 1e-6
          dot = vector_b.dot(vector_a)
          next if dot < -1e-6
          next if dot > vector_b.length**2
          isGroundLevel = false
          break
        end
        break unless isGroundLevel
      end

      ground_level_vertices << midpoint if isGroundLevel
    end
  end

  ground_level_plane = unless ground_level_vertices.length < 3 then
    OpenStudio::Plane.new(ground_level_vertices)
  else
    OpenStudio::Plane.new(OpenStudio::Point3d.new, OpenStudio::Vector3d.new(0, 0, 1))
  end

  # split edges to select thermal bridges

  # os_model.getSpaces.each do |space|
    # group = space.drawing_interface.entity

    # edges = group.entities.grep(Sketchup::Edge).select do |edge| edge.faces.length.eql?(1) end

    # while true do
      # split = false

      # edges.each do |edge|
        # points = edge.vertices.map do |vertex| vertex.position end

        # edges.each do |other_edge|
          # other_edge.vertices.each do |vertex|
            # point = vertex.position
            # next if (points.map do |x| x.distance(point) end.min).to_f < 1e-6
            # next unless Geom.point_in_polygon_2D(point, points, true)

            # split = true
            # edges << edge.split(point)
            # break
          # end
          # break if split
        # end
        # break if split
      # end

      # break unless split
    # end

    # edges.each do |edge|
      # line = group.entities.add_line(edge.start.position, edge.end.position)
      # line.find_faces
    # end

    # group.entities.grep(Sketchup::Edge).select do |edge| edge.faces.length.eql?(0) end.each do |edge| edge.erase! end
  # end

  new_groups, os2su = SketchUp.get_os2su(os_model, false)
  su2os = os2su.invert
  os_model.getShadingSurfaceGroups.each do |group| group.drawing_interface.entity.locked = true end

  os_model.getSurfaces.each do |surface|
    next unless surface.surfaceType.eql?("RoofCeiling") && surface.outsideBoundaryCondition.eql?("Surface")

    os2su[surface].edges.each do |edge| edge.hidden = true end
  end

  # he1 indicators limits

  u_lims_cte = [
    [0.8, 0.7, 0.56, 0.49, 0.41, 0.37],
    [0.55, 0.5, 0.44, 0.4, 0.35, 0.33],
    [0.9, 0.8, 0.75, 0.7, 0.65, 0.59],
    [3.2, 2.7, 2.3, 2.1, 1.8, 1.8],
    [5.7, 5.7, 5.7, 5.7, 5.7, 5.7],
    [1.9, 1.8, 1.55, 1.35, 1.2, 1.0],
    [1.4, 1.4, 1.2, 1.2, 1.2, 1.0],
    [1.35, 1.25, 1.1, 0.95, 0.85, 0.7]
  ]

  k_lims_cte = case residencialOTerciario
  when "Residencial"
    [
      [0.67, 0.6, 0.58, 0.53, 0.48, 0.43],
      [0.86, 0.8, 0.77, 0.72, 0.67, 0.62]
    ]
  else
    [
      [0.96, 0.81, 0.76, 0.65, 0.54, 0.43],
      [1.12, 0.98, 0.92, 0.82, 0.70, 0.59]
    ]
  end

  column = ["alpha", "A", "B", "C", "D", "E"].index do |x| x.eql?(zonaClimatica[0...-1]) end
  u_lims = u_lims_cte.map do |row| row[column] end

  volume, area_int, w_k_lim, w_k_count = 0.0, 0.0, 0.0, 0
  spaces_neighbours = os_model.getSpaces.map do |space|
    next unless space.partofTotalFloorArea

    volume += Geometry.get_volume(space)
    space.surfaces.each do |surface|
      area = surface.grossArea

      area = case surface.outsideBoundaryCondition
      when "Outdoors", "Ground"
        area
      when "Surface"
        adjacent_space = surface.adjacentSurface.get.space.get
        adjacent_space.partofTotalFloorArea ? 0.0 : area
      else
        0.0
      end
      next if area < 1e-6

      u_lim = case surface.outsideBoundaryCondition
      when "Outdoors"
        u_lims[ surface.surfaceType.eql?("RoofCeiling") ? 1 : 0 ]

      else
        u_lims[2]
      end
      sub_surfaces_area = surface.subSurfaces.map do |sub_surface| sub_surface.grossArea end
      # w_k_lim = [surface.netArea * u_lim, (sub_surfaces_area.max || 0.0) * u_lims[3], w_k_lim].max
      w_k_count += (1 + sub_surfaces_area.length)

      area_int += area
    end

    space_neighbours = space.surfaces.map do |surface|
      adjacent_surface = surface.adjacentSurface
      next if adjacent_surface.empty?

      adjacent_space = adjacent_surface.get.space
      next if adjacent_space.empty?

      space_neighbour = adjacent_space.get
      next if space_neighbour.eql?(space)
      next unless space_neighbour.partofTotalFloorArea
      next unless surface.isAirWall || surface.subSurfaces.length > 0

      space_neighbour
    end.compact

    [space, space_neighbours]
  end.compact.to_h

  if area_int < 1e-6 then
    UI.messagebox("This building has no envelope.")
  else
    f_array = k_lims_cte.map do |row| row[column] end
    au_lim = area_int * [[ThermalBridges.interpolate([1.0, 4.0], f_array, volume / area_int), f_array.max].min, f_array.min].max
    w_k_lim = 3 * au_lim / w_k_count

    # sketchup dialog

    inputbox_file = "#{File.dirname(__FILE__)}/Kglobal/Kglobal.html"
    dialog = UI::HtmlDialog.new({:dialog_title => "K global", :preferences_key => "com.example.html-input", :scrollable => true, :resizable => false, :style => UI::HtmlDialog::STYLE_DIALOG})
    dialog.set_size(1800, 1000)
    dialog.set_file(inputbox_file)

    construction_set_hash = {
      "exterior_surface" => [
        "wall",
        "floor",
        "roof"
      ],
      "interior_surface" => [
        "wall",
        "floor",
        "ceiling"
      ],
      "ground_contact_surface" => [
        "wall",
        "floor",
        "ceiling"
      ],
      "exterior_sub_surface" => [
        "fixed_window",
        "operable_window",
        "door",
        "glass_door",
        "overhead_door",
        "skylight"
      ],
      "interior_sub_surface" => [
        "fixed_window",
        "operable_window",
        "door"
      ],
      "other" => [
        "interior_partition",
        "adiabatic_surface"
      ]
    }

    dialog.add_action_callback("add_construction_set_layout") do |action_context|
      script = []

      script << "var construction_set = document.getElementById('construction_set')"
      construction_set_hash.each do |default_constructions_id, default_constructions|
        is_construction_set = !construction_set_hash[default_constructions_id].nil?
        script << "var default_constructions_div = document.createElement('div')"
        script << "default_constructions_div.setAttribute('id', '#{default_constructions_id}')"
        script << "default_constructions_div.style.clear = 'both'"
        script << "default_constructions_div.style.width = '100%'"
        script << "default_constructions_div.style.height = '#{50+100*((default_constructions.length-1)/3+1)}px'"
        script << "var default_constructions_name = document.createElement('p')"
        script << "default_constructions_name.appendChild(document.createTextNode('#{Utilities.capitalize_all(default_constructions_id, " ")}#{ is_construction_set ? " Constructions" : "" }'))"
        script << "default_constructions_div.appendChild(default_constructions_name)"
        default_constructions.each do |default_construction_id|
          script << "var default_construction_div = document.createElement('div')"
          script << "default_construction_div.setAttribute('id', '#{default_constructions_id}_#{default_construction_id}')"
          script << "default_construction_div.style.float = 'left'"
          script << "default_construction_div.style.width = '30%'"
          script << "default_construction_div.style.height = '100px'"
          script << "default_construction_div.style.marginBottom = '10px'"
          script << "default_construction_div.style.marginRight = '10px'"
          script << "default_construction_div.classList.add('drop')"
          script << "var default_construction_name = document.createElement('p')"
          script << "default_construction_name.appendChild(document.createTextNode('#{Utilities.capitalize_all(default_construction_id, " ")}#{ is_construction_set ? "s" : "" }'))"
          script << "default_construction_div.appendChild(default_construction_name)"
          script << "var default_construction = document.createElement('p')"
          script << "default_construction_div.appendChild(default_construction)"
          script << "default_constructions_div.appendChild(default_construction_div)"
        end
        script << "construction_set.appendChild(default_constructions_div)"
      end

      dialog.execute_script(script.join(";"))
    end

    os_type = {
      "construction_sets" => "DefaultConstructionSet",
      "constructions" => "LayeredConstruction",
      "air_gaps" => "AirGap",
      "materials" => "StandardOpaqueMaterial",
      "glazings" => "SimpleGlazing",
      "frames" => "WindowPropertyFrameAndDivider",
      "thermal_bridges" => "MasslessOpaqueMaterial"
    }

    # load the data from the JSON file into a ruby hash

    cte_materials_hash = JSON.parse(File.read("#{File.dirname(__FILE__)}/src/CTE/CatalogoMaterialesCTE.json"))

    cte_materials_hash.each do |group, materials|
      materials.each do |name, properties|
        new_material = OpenStudio::Model::StandardOpaqueMaterial.new(os_model, "Smooth", properties["thickness"], properties["lambda"], properties["rho"], properties["cp"])
        new_material.setName("CTE - #{group} - #{name}")
        new_material.additionalProperties.setFeature("material", name)
        new_material.additionalProperties.setFeature("editable", properties["editable"])
        mu = properties["mu"].to_f
        new_material.additionalProperties.setFeature("mu", mu)
        new_material.additionalProperties.setFeature("eq_air_gap", mu*new_material.thickness)

        cte_materials_hash[group][name] = new_material
      end
    end

    zc_thermal_bridge_types = ThermalBridges.get_zc_thermal_bridge_types
    cte_thermal_bridge_types = ThermalBridges.get_cte_thermal_bridge_types

    dialog.add_action_callback("add_lists") do |action_context|
      script = Constructions.add_interface_objects(os_model, os_type)

      script << "var left = document.getElementById('left')"
      script << "var materials = document.getElementById('materials').parentNode"
      cte_materials_hash.each do |group, materials|
        script << "var group_ul = document.createElement('ul')"
        script << "group_ul.classList.add('hide')"
        script << "group_ul.classList.add('cte')"
        script << "var group_li = document.createElement('li')"
        script << "group_li.appendChild(document.createTextNode('#{group}'))"
        group_id = group.downcase.gsub(" ", "_")
        script << "group_li.setAttribute('id', '#{group_id}')"
        script << "groups_id.push('#{group_id}')"
        script << "var materials_ul = document.createElement('ul')"
        materials.each do |name, material|
          material.additionalProperties.setFeature("interface", true)
          script << "var material_li = document.createElement('li')"
          script << "material_li.appendChild(document.createTextNode('#{name}'))"
          script << "materials_ul.appendChild(material_li)"
        end
        script << "group_li.appendChild(materials_ul)"
        script << "group_ul.appendChild(group_li)"
        script << "left.insertBefore(group_ul, materials)"
      end

      script << "var thermal_bridge_type = document.getElementById('thermal_bridge_type')"
      script << "var thermal_bridges = document.getElementById('thermal_bridges').parentNode"
      zc_thermal_bridge_types.each do |thermal_bridge_type|
        display_name = thermal_bridge_type.gsub("_", " ").capitalize

        script << "var option = document.createElement('option')"
        script << "option.innerHTML = '#{display_name}'"
        script << "option.value = '#{thermal_bridge_type}'"
        script << "thermal_bridge_type.appendChild(option)"

        script << "var group_ul = document.createElement('ul')"
        script << "group_ul.classList.add('hide')"
        script << "group_ul.classList.add('cte')"
        script << "var group_li = document.createElement('li')"
        script << "group_li.appendChild(document.createTextNode('#{display_name}'))"
        script << "group_li.setAttribute('id', '#{thermal_bridge_type}')"
        script << "thermal_bridges_id.push('#{thermal_bridge_type}')"
        script << "var materials_ul = document.createElement('ul')"
        choices = ThermalBridges.get_ngroups(thermal_bridge_type).times.map do |x| "Grupo #{x+1}" end
        choices.each do |choice|
          script << "var material_li = document.createElement('li')"
          script << "material_li.appendChild(document.createTextNode('#{choice}'))"
          script << "materials_ul.appendChild(material_li)"
        end
        script << "group_li.appendChild(materials_ul)"
        script << "group_ul.appendChild(group_li)"
        script << "left.insertBefore(group_ul, thermal_bridges)"
      end

      dialog.execute_script(script.join(";"))
    end

    standards_information_hash = {
      "intended_surface_type" => [""] + OpenStudio::Model::StandardsInformationConstruction.intendedSurfaceTypeValues.select do |x| x.include?("Window") || x.include?("Skylight") || x.include?("Door") end,
      "fenestration_type" => [""] + OpenStudio::Model::StandardsInformationConstruction.fenestrationTypeValues,
      "fenestration_frame_type" => [""] + OpenStudio::Model::StandardsInformationConstruction.fenestrationFrameTypeValues
    }

    dialog.add_action_callback("add_standards_information") do |action_context|
      script = []

      standards_information_hash.each do |id, options|
        script << "var select = document.getElementById('#{id}')"
        options.each do |option|
          script << "var option = document.createElement('option')"
          script << "option.innerHTML = '#{option}'"
          script << "select.appendChild(option)"
        end
      end

      dialog.execute_script(script.join(";"))
    end

    def self.render_white(su_model, new_groups)
      su_model.rendering_options["EdgeColorMode"] = 1
      su_model.rendering_options["DrawDepthQue"] = 0

      white = Sketchup::Color.new(255, 255, 255, 1.0)
      black = Sketchup::Color.new(0, 0, 0, 1.0)

      new_groups.each do |group|
        group.entities.grep(Sketchup::Face).each do |face|
          SketchUp.set_material(face, white)
        end

        group.entities.grep(Sketchup::Edge).each do |edge|
          SketchUp.set_material(edge, black)
        end
      end
    end

    render = nil

    dialog.add_action_callback("render_white") do |action_context|
      self.render_white(su_model, new_groups) if render.eql?("input")
    end

    def self.render_by_selection(os_model, id, li, zc_thermal_bridge_types, new_groups, os2su)
      self.render_white(Sketchup.active_model, new_groups)

      white = Sketchup::Color.new(255, 255, 255, 1.0)
      grey = Sketchup::Color.new(96, 80, 76, 1.0)
      green = Sketchup::Color.new(120, 157, 74, 1.0)

      case id
      when "construction_sets"
        os_model.getSpaces.each do |space|
          construction_set = space.defaultConstructionSet

          color = if construction_set.empty? then
            grey
          elsif construction_set.get.name.get.to_s.eql?(li) then
            green
          end
          next if color.nil?

          space.surfaces.each do |surface|
            SketchUp.set_material(os2su[surface], color)
            surface.subSurfaces.each do |sub_surface| SketchUp.set_material(os2su[sub_surface], color) end
          end
        end

      when "constructions"
        os_model.getSurfaces.each do |surface|
          construction = surface.construction

          color = if construction.empty? then
            grey
          elsif construction.get.name.get.to_s.eql?(li) then
            green
          end
          next if color.nil?

          SketchUp.set_material(os2su[surface], color)
        end

      when "materials"

      when "glazings", "frames"
        os_model.getSubSurfaces.each do |sub_surface|
          object = case id
          when "glazings"
            sub_surface.construction

          when "frames"
            sub_surface.windowPropertyFrameAndDivider
          end

          color = if object.empty? then
            grey
          elsif object.get.name.get.to_s.eql?(li) then
            green
          end
          next if color.nil?

          SketchUp.set_material(os2su[sub_surface], color)
        end

      else
        if (zc_thermal_bridge_types + ["thermal_bridges"]).include?(id) then
          su_model = Sketchup.active_model
          su_model.rendering_options["EdgeColorMode"] = 0
          su_model.rendering_options["DrawDepthQue"] = 1
          su_model.rendering_options["DepthQueWidth"] = 10

          case id
          when "thermal_bridges"
            thermal_bridge = os_model.getMasslessOpaqueMaterialByName(li).get
            thermal_bridge_type = thermal_bridge.additionalProperties.getFeatureAsString("thermal_bridge_type").get
            exterior_wall2others = thermal_bridge.additionalProperties.getFeatureAsString("exterior_wall2others")

            unless exterior_wall2others.empty? then
              exterior_wall2others = JSON.parse(exterior_wall2others.get)

              exterior_wall2others.each do |exterior_wall, others|
                face = os2su[os_model.getSurfaceByName(exterior_wall).get]
                others.each do |other|
                  planar_surface = case thermal_bridge_type
                  when "jamba", "dintel", "alfeizar", "capialzado"
                    os_model.getSubSurfaceByName(other).get
                  else
                    os_model.getSurfaceByName(other).get
                  end
                  other_face = os2su[planar_surface]

                  face.edges.each do |edge|
                    next unless edge.used_by?(other_face)

                    SketchUp.set_material(edge, green)
                  end
                end
              end
            end
          else
            group = li[-1].to_i
            os_model.getSurfaces.each do |surface|
              thermal_bridges = surface.additionalProperties.getFeatureAsString("thermal_bridges")
              next if thermal_bridges.empty?
              thermal_bridges = JSON.parse(thermal_bridges.get)

              face = os2su[surface]
              thermal_bridges[id][group].each do |other|
                planar_surface = case id
                when "hueco", "capialzado"
                  os_model.getSubSurfaceByName(other).get
                else
                  os_model.getSurfaceByName(other).get
                end
                other_face = os2su[planar_surface]

                face.edges.each do |edge|
                  next unless edge.used_by?(other_face)

                  SketchUp.set_material(edge, green)
                end
              end
            end
          end
        end
      end
    end

    dialog.add_action_callback("set_render") do |action_context, option, id, li|
      script = []

      render = option

      self.render_by_selection(os_model, id, li, zc_thermal_bridge_types, new_groups, os2su) if render.eql?("input")
      self.render_white(Sketchup.active_model, new_groups) if render.eql?("mirror")

      script << "var tabs = document.getElementById('output').getElementsByClassName('btn btn-success')"
      script << "sketchup.compute_k_global(tabs.length === 0 ? null : tabs[0].value)"

      dialog.execute_script(script.join(";"))
    end

    dialog.add_action_callback("show_li") do |action_context, id, li|
      script = []

      script << "document.getElementById('right').classList.remove('hide')"

      li = Utilities.fix_name(li)

      case id
      when "construction_sets"
        construction_set = os_model.getDefaultConstructionSetByName(li).get

        default_surface_constructions, construction = nil, nil
        construction_set_hash.each do |default_constructions_id, default_constructions|
          eval("default_surface_constructions = construction_set.default#{Utilities.capitalize_all(default_constructions_id)}Constructions.get") unless default_constructions_id.eql?("other")

          default_constructions.each do |default_construction_id|
            surface_type = ["roof", "ceiling"].include?(default_construction_id) ? "roof_ceiling" : default_construction_id
            eval("construction = #{ default_constructions_id.eql?("other") ? "construction_set" : "default_surface_constructions" }.#{Utilities.capitalize_all_but_first(surface_type)}Construction")
            script << "var p = document.getElementById('#{default_constructions_id}_#{default_construction_id}').getElementsByTagName('p')[1]"
            script << if construction.empty? || construction.get.name.get.to_s.include?("\n") then
              "p.innerHTML = ''"
            else
              "p.innerHTML = '#{construction.get.name.get.to_s}'"
            end
          end
        end

      when "constructions"
        layered_construction = os_model.getLayeredConstructionByName(li).get
        script << "document.getElementById('uvalue').value = parseFloat(#{layered_construction.thermalConductance.get}).toFixed(3)"

        reversed_type = Constructions.get_reversed_type(os_model, layered_construction)
        num_layers = layered_construction.layers.length
        script << "document.getElementById('edge_insulation_check').disabled = #{ reversed_type > 1 || num_layers < 1 }"
        script << "document.getElementById('internal_source_check').disabled = #{ reversed_type.eql?(3) ||  num_layers < 2 }"
        script << "var sort = document.getElementsByClassName('glyphicon-sort')[0]"
        script << "sort.classList.#{ reversed_type.eql?(1) ? "remove" : "add" }('hide')"
        if reversed_type < 2 then
          script << "sort.previousElementSibling.classList.remove('hide')"
          script << "document.getElementById('reverse_construction').classList.add('hide')"
        else
          script << "sort.previousElementSibling.classList.add('hide')"
          script << "document.getElementById('reverse_construction').classList.remove('hide')"
          reversed_construction = Constructions.get_reversed_construction(os_model, layered_construction)
          script << "document.getElementById('reversed_construction').getElementsByTagName('p')[1].innerHTML = '#{reversed_construction.name.get.to_s}'"
        end
        script << "var tbody = document.getElementsByTagName('tbody')[#{ reversed_type.eql?(3) ? 0 : 1 }]"

        script << "document.getElementById('interior_horizontal_insulation').classList.add('hide')"
        script << "document.getElementById('exterior_vertical_insulation').classList.add('hide')"
        edge_insulation = os_model.getFoundationKivaByName(li)

        if edge_insulation.empty? then
          script << "document.getElementById('edge_insulation_check').checked = false"
        else
          script << "sort.classList.add('hide')"
          script << "document.getElementById('edge_insulation_check').checked = true"
          script << "document.getElementById('interior_horizontal_insulation').classList.remove('hide')"
          script << "document.getElementById('exterior_vertical_insulation').classList.remove('hide')"

          edge_insulation, insulation_material, length = edge_insulation.get, nil, nil
          [["interior", "horizontal", "width"], ["exterior", "vertical", "depth"]].each do |interior_exterior, horizontal_vertical, width_depth|
            eval("insulation_material = edge_insulation.#{interior_exterior}#{horizontal_vertical.capitalize}InsulationMaterial")
            if insulation_material.empty? then
              script << "document.getElementById('#{interior_exterior}_#{horizontal_vertical}_insulation_thickness').value = null"
              script << "document.getElementById('#{interior_exterior}_#{horizontal_vertical}_insulation_material').getElementsByTagName('p')[1].innerHTML = ''"
              script << "document.getElementById('#{interior_exterior}_#{horizontal_vertical}_insulation_#{width_depth}').value = null"
            else
              insulation_material = insulation_material.get
              script << "document.getElementById('#{interior_exterior}_#{horizontal_vertical}_insulation_thickness').value = parseFloat(#{Utilities.convert(Constructions.get_layer_thickness(insulation_material), "m", "cm")}).toFixed(1)"
              script << "document.getElementById('#{interior_exterior}_#{horizontal_vertical}_insulation_material').getElementsByTagName('p')[1].innerHTML = '#{insulation_material.additionalProperties.getFeatureAsString("material")}'"
              eval("length = edge_insulation.#{interior_exterior}#{horizontal_vertical.capitalize}Insulation#{width_depth.capitalize}")
              script << "document.getElementById('#{interior_exterior}_#{horizontal_vertical}_insulation_#{width_depth}').value = #{length.empty? ? "null" : "parseFloat(#{length.get}).toFixed(1)" }"
            end
          end
        end

        script << "$('#layers tbody tr').remove()"
        layered_construction.layers.each_with_index do |layer, index|
          script << "var row = tbody.insertRow(#{index})"
          script << "var index = row.insertCell(0)"
          script << "index.innerHTML = '#{index+1}'"
          script << "var layer_name = row.insertCell(1)"
          material = layer.additionalProperties.getFeatureAsString("material").get
          script << "layer_name.innerHTML = '#{material}'"
          script << "var thk = row.insertCell(2)"
          script << "thk.innerHTML = parseFloat(#{Utilities.convert(Constructions.get_layer_thickness(layer), "m", "cm")}).toFixed(1)"
          editable = layer.additionalProperties.getFeatureAsBoolean("editable").get
          script << "thk.contentEditable = tbody.classList.contains('editable') && #{editable}"
          opaque_material = layer.to_OpaqueMaterial
          thermal_resistance = opaque_material.empty? ? 0.0 : opaque_material.get.thermalResistance
          script << "var thermal_r = row.insertCell(3)"
          script << "thermal_r.innerHTML = parseFloat(#{thermal_resistance}).toFixed(3)"
          script << "var eq_air_gap = row.insertCell(4)"
          script << "eq_air_gap.innerHTML = parseFloat(#{layer.additionalProperties.getFeatureAsDouble("eq_air_gap").get}).toFixed(2)"
        end

        construction_with_internal_source = layered_construction.to_ConstructionWithInternalSource
        if construction_with_internal_source.empty? then
          script << "document.getElementById('internal_source_check').checked = false"
        else
          script << "document.getElementById('internal_source_check').checked = true"
          script << "add_internal_source_row(tbody, #{construction_with_internal_source.get.sourcePresentAfterLayerNumber})"
        end

      when "glazings"
        glazing = os_model.getSimpleGlazingByName(li).get
        script << "document.getElementById('ufactor').value = parseFloat(#{glazing.uFactor}).toFixed(2)"
        script << "document.getElementById('ufactor').readOnly = false"
        script << "document.getElementById('shgc').value = parseFloat(#{glazing.solarHeatGainCoefficient}).toFixed(2)"
        script << "document.getElementById('shgc').readOnly = false"
        vlt = glazing.visibleTransmittance
        script << "document.getElementById('vlt').value = #{ vlt.empty? ? "null" : "parseFloat(#{vlt.get}).toFixed(2)" }"
        script << "document.getElementById('vlt').readOnly = false"

        standards_information = os_model.getLayeredConstructionByName(li).get.standardsInformation
        standards_information_hash.each do |id, options|
          type = nil
          eval("type = standards_information.#{Utilities.capitalize_all_but_first(id)}")
          script << "document.getElementById('#{id}').selectedIndex = '#{ type.empty? ? 0 : options.find_index(type.get) }'"
        end

      when "frames"
        frame = os_model.getWindowPropertyFrameAndDividerByName(li).get
        script << "document.getElementById('frame_width').value = parseFloat(#{Utilities.convert(frame.frameWidth, "m", "cm")}).toFixed(0)"
        frame_conductance = frame.frameConductance
        script << "document.getElementById('frame_conductance').value = #{ frame_conductance.empty? ? "null" : "parseFloat(#{frame_conductance.get}).toFixed(1)"}"
        script << "document.getElementById('frame_setback').value = parseFloat(#{Utilities.convert(frame.outsideRevealDepth, "m", "cm")}).toFixed(0)"
        frame_reflectance = frame.additionalProperties.getFeatureAsDouble("frame_reflectance")
        if frame_reflectance.empty? then
          script << "document.getElementById('frame_colour').value = -1"
          script << "document.getElementById('frame_reflectance').readOnly = false"
        else
          script << "document.getElementById('frame_colour').value = #{frame_reflectance.get.round(1)}"
          script << "document.getElementById('frame_reflectance').readOnly = true"
        end
        frame_reflectance = 1 - frame.frameSolarAbsorptance
        script << "document.getElementById('frame_reflectance').value = parseFloat(#{frame_reflectance}).toFixed(1)"
      when "thermal_bridges"
        thermal_bridge = os_model.getMasslessOpaqueMaterialByName(li).get
        script << "document.getElementById('thermal_bridge_type').value = '#{thermal_bridge.additionalProperties.getFeatureAsString("thermal_bridge_type").get}'"
        script << "document.getElementById('thermal_bridge_psi').value = parseFloat(#{1.0 / thermal_bridge.thermalResistance}).toFixed(2)"

      else
        unless zc_thermal_bridge_types.include?(id) then
          material = Constructions.divide_materials_interface(os_model, li).first.first.to_StandardOpaqueMaterial.get
          script << "document.getElementById('lambda').value = parseFloat(#{material.conductivity}).toFixed(3)"
          script << "document.getElementById('lambda').readOnly = #{ id.eql?("materials") ? false : true }"
          script << "document.getElementById('rho').value = parseFloat(#{material.density}).toFixed(0)"
          script << "document.getElementById('rho').readOnly = #{ id.eql?("materials") ? false : true }"
          script << "document.getElementById('cp').value = parseFloat(#{material.specificHeat}).toFixed(0)"
          script << "document.getElementById('cp').readOnly = #{ id.eql?("materials") ? false : true }"
          mu = material.additionalProperties.getFeatureAsDouble("mu")
          script << "document.getElementById('mu').value = #{ mu.empty? ? "null" : "parseFloat(#{mu.get}).toFixed(0)" }"
          script << "document.getElementById('mu').readOnly = #{ id.eql?("materials") ? false : true }"
        end
      end

      script << "var tabs = document.getElementById('output').getElementsByClassName('btn btn-success')"
      script << "sketchup.compute_k_global(tabs.length === 0 ? null : tabs[0].value)"
      self.render_by_selection(os_model, id, li, zc_thermal_bridge_types, new_groups, os2su) if render.eql?("input")

      dialog.execute_script(script.join(";"))
    end

    dialog.add_action_callback("add_object") do |action_context, id|
      script = []

      new_object = nil
      eval("new_object = OpenStudio::Model::#{ id.eql?("constructions") ? "Construction" : os_type[id] }.new(os_model)")
      new_object.additionalProperties.setFeature("interface", true)
      name = new_object.name.get.to_s
      case id
      when "construction_sets"
        construction_set_hash.each do |default_constructions_id, default_constructions|
          unless default_constructions_id.eql?("other") then
            eval("default_surface_constructions = new_object.default#{Utilities.capitalize_all(default_constructions_id)}Constructions")
            default_surface_constructions = if default_surface_constructions.empty? then
              eval("OpenStudio::Model::Default#{default_constructions_id.end_with?("_sub_surface") ? "Sub" : ""}SurfaceConstructions.new(os_model)")
            else
              default_surface_constructions.get
            end
            eval("new_object.setDefault#{Utilities.capitalize_all(default_constructions_id)}Constructions(default_surface_constructions)")
          end
        end

      when "materials"
        new_object.additionalProperties.setFeature("material", name)
        new_object.additionalProperties.setFeature("editable", true)
        new_object.additionalProperties.setFeature("mu", 1.0)
        new_object.additionalProperties.setFeature("eq_air_gap", Constructions.get_layer_thickness(new_object))

      when "glazings", "thermal_bridges"
        new_construction = OpenStudio::Model::Construction.new([new_object])
        new_construction.setName(name)
        name = new_construction.name.get.to_s
        new_object.setName(name)

        case id
        when "thermal_bridges"
          new_object.additionalProperties.setFeature("thermal_bridge_type", zc_thermal_bridge_types.first)
          new_object.additionalProperties.setFeature("exterior_wall2others", {}.to_json)
          new_object.setThermalResistance(1.0 / ThermalBridges.get_default_psi)
          new_object.setThermalAbsorptance(0.9)
          new_object.setSolarAbsorptance(0.7)
          new_object.setVisibleAbsorptance(0.7)
        end
      end
      script << "add_li('#{id}', '#{name}')"

      dialog.execute_script(script.join(";"))
    end

    dialog.add_action_callback("rename_object") do |action_context, id, old_name, new_name|
      script = []

      old_name, new_name = Utilities.fix_name(old_name), Utilities.fix_name(new_name)
      object = nil
      eval("object = os_model.get#{os_type[id]}ByName(old_name).get")
      object.setName(new_name)
      new_name = object.name.get.to_s
      case id
      when "materials"
        Constructions.get_opaque_materials(os_model, old_name).each do |material| material.additionalProperties.setFeature("material", new_name) end

      when "glazings", "thermal_bridges"
        construction = os_model.getConstructionByName(old_name).get
        construction.setName(new_name)
        object.setName(construction.name.get.to_s)
      end
      script << "document.getElementById('old_name').parentNode.innerHTML = '#{new_name}'"

      dialog.execute_script(script.join(";"))
    end

    dialog.add_action_callback("duplicate_object") do |action_context, id, object_name|
      script = []

      object_name = Utilities.fix_name(object_name)
      new_object = nil
      eval("new_object = os_model.get#{os_type[id]}ByName(object_name).get.clone(os_model).to_#{os_type[id]}.get")
      new_name = new_object.name.get.to_s
      case id
      when "construction_sets"
        construction_set_hash.each do |default_constructions_id, default_constructions|
          next if default_constructions_id.eql?("other")
          default_surface_constructions = nil
          eval("default_surface_constructions = new_object.default#{Utilities.capitalize_all(default_constructions_id)}Constructions")
          next if default_surface_constructions.empty?
          eval("new_object.setDefault#{Utilities.capitalize_all(default_constructions_id)}Constructions(default_surface_constructions.get.clone(os_model).to_Default#{default_constructions_id.end_with?("_sub_surface") ? "Sub" : ""}SurfaceConstructions.get)")
        end

      when "constructions"
        edge_insulation = os_model.getFoundationKivaByName(object_name)
        unless edge_insulation.empty? then
          edge_insulation = edge_insulation.get.clone(os_model).to_FoundationKiva.get
          edge_insulation.setName(new_name)
        end

      when "materials"
        new_object.additionalProperties.setFeature("material", new_name)

      when "glazings", "thermal_bridges"
        new_construction = OpenStudio::Model::Construction.new([new_object])
        new_construction.setName(new_name)
        new_object.setName(new_construction.name.get.to_s)
        case id
        when "thermal_bridges"
          new_object.additionalProperties.setFeature("exterior_wall2others", {}.to_json)
        end
      end
      script << "add_li('#{id}', '#{new_object.name.get.to_s}')"

      dialog.execute_script(script.join(";"))
    end

    dialog.add_action_callback("reverse_construction") do |action_context, construction_name|
      script = []

      construction_name = Utilities.fix_name(construction_name)
      layered_construction = os_model.getLayeredConstructionByName(construction_name).get
      reversed_construction = Constructions.get_reversed_construction(os_model, layered_construction)
      reversed_construction.additionalProperties.setFeature("interface", true)
      reversed_construction.additionalProperties.setFeature("reversed", true)
      script << "add_li('constructions', '#{reversed_construction.name.get.to_s}')"

      dialog.execute_script(script.join(";"))
    end

    dialog.add_action_callback("remove_object") do |action_context, id, object_name|
      script = []

      object_name = Utilities.fix_name(object_name)
      object = nil
      eval("object = os_model.get#{os_type[id]}ByName(object_name).get")
      case id
      when "constructions"
        reversed_type = Constructions.get_reversed_type(os_model, object)
        if reversed_type.eql?(2) then
          reversed_construction = Constructions.get_reversed_construction(os_model, object)
          script << "remove_li('constructions', '#{reversed_construction.name.get.to_s}')"
          reversed_construction.remove
        end

      when "materials"
        Constructions.divide_materials_interface(os_model, object_name)[1].each(&:remove)

      when "glazings", "thermal_bridges"
        os_model.getConstructionByName(object_name).get.remove
        case id
        when "thermal_bridges"
          thermal_bridge_type = object.additionalProperties.getFeatureAsString("thermal_bridge_type").get
          JSON.parse(object.additionalProperties.getFeatureAsString("exterior_wall2others").get).each do |exterior_wall_name, others|
            exterior_wall = os_model.getSurfaceByName(exterior_wall_name).get
            thermal_bridges = JSON.parse(exterior_wall.additionalProperties.getFeatureAsString("thermal_bridges").get)
            thermal_bridges[thermal_bridge_type][0] = thermal_bridges[thermal_bridge_type][0].select do |other_name| !others.include?(other_name) end

            if thermal_bridges.find do |thermal_bridge_type, value| !value.find do |others| !others.empty? end.nil? end.nil? then
              exterior_wall.additionalProperties.resetFeature("thermal_bridges")
            else
              exterior_wall.additionalProperties.setFeature("thermal_bridges", thermal_bridges.to_json)
            end
          end
        end

      when "frames"
        os_model.getSubSurfaces.each_with_index do |sub_surface, index|
          window_property_frame_and_divider = sub_surface.windowPropertyFrameAndDivider
          next if window_property_frame_and_divider.empty?
          next unless window_property_frame_and_divider.get.eql?(object)

          sub_surface.resetWindowPropertyFrameAndDivider
        end
      end
      object.remove

      dialog.execute_script(script.join(";"))
    end

    dialog.add_action_callback("add_default_construction") do |action_context, id, construction_set_name, object_name|
      construction_set_name = Utilities.fix_name(construction_set_name)
      construction_set = os_model.getDefaultConstructionSetByName(construction_set_name).get

      Constructions.add_default_construction(os_model, object_name, id, construction_set)

      dialog.execute_script("sketchup.show_li('construction_sets', '#{construction_set_name}')")
    end

    dialog.add_action_callback("remove_default_construction") do |action_context, id, construction_set_name|
      construction_set_name = Utilities.fix_name(construction_set_name)
      construction_set = os_model.getDefaultConstructionSetByName(construction_set_name).get

      Constructions.remove_default_construction(os_model, id, construction_set)

      dialog.execute_script("sketchup.show_li('construction_sets', '#{construction_set_name}')")
    end

    dialog.add_action_callback("toggle_layered_construction") do |action_context, construction_name|
      construction_name = Utilities.fix_name(construction_name)
      layered_construction = os_model.getLayeredConstructionByName(construction_name).get
      reversed_construction = Constructions.get_reversed_type(os_model, layered_construction).eql?(2) ? Constructions.get_reversed_construction(os_model, layered_construction) : nil

      layers = layered_construction.layers.map do |layer| layer.to_OpaqueMaterial.get end
      new_layered_construction = if layered_construction.to_Construction.empty? then
        OpenStudio::Model::Construction.new(layers)
      else
        OpenStudio::Model::ConstructionWithInternalSource.new(layers)
      end
      layered_construction.remove

      new_layered_construction.setName(construction_name)
      new_layered_construction.additionalProperties.setFeature("interface", true)

      unless reversed_construction.nil? then
        reversed_construction_name = reversed_construction.name.get.to_s
        reversed_construction.remove
        new_reversed_construction = Constructions.get_reversed_construction(os_model, new_layered_construction)
        new_reversed_construction.setName(reversed_construction_name)
        new_reversed_construction.additionalProperties.setFeature("reversed", true)
      end

      dialog.execute_script("sketchup.show_li('constructions', '#{construction_name}')")
    end

    dialog.add_action_callback("toggle_edge_insulation") do |action_context, construction_name|
      construction_name = Utilities.fix_name(construction_name)
      edge_insulation = os_model.getFoundationKivaByName(construction_name)
      if edge_insulation.empty? then
        edge_insulation = OpenStudio::Model::FoundationKiva.new(os_model)
        edge_insulation.setName(construction_name)
        dialog.execute_script("sketchup.show_li('constructions', '#{construction_name}')")
      else
        edge_insulation.get.remove
      end
    end

    dialog.add_action_callback("add_layer") do |action_context, construction_name, material_name|
      construction_name = Utilities.fix_name(construction_name)
      layered_construction = os_model.getLayeredConstructionByName(construction_name).get
      reversed_construction = Constructions.get_reversed_type(os_model, layered_construction).eql?(2) ? Constructions.get_reversed_construction(os_model, layered_construction) : nil

      num_layers = layered_construction.layers.length
      layer = Constructions.get_material(os_model, material_name)
      layered_construction.insertLayer(num_layers, layer)

      unless reversed_construction.nil? then
        reversed_construction_name = reversed_construction.name.get.to_s
        reversed_construction.remove
        new_reversed_construction = Constructions.get_reversed_construction(os_model, layered_construction)
        new_reversed_construction.setName(reversed_construction_name)
        new_reversed_construction.additionalProperties.setFeature("reversed", true)
      end

      dialog.execute_script("sketchup.show_li('constructions', '#{construction_name}')")
    end

    dialog.add_action_callback("edit_layer") do |action_context, construction_name, thickness, layer_index|
      construction_name = Utilities.fix_name(construction_name)
      layered_construction = os_model.getLayeredConstructionByName(construction_name).get
      reversed_construction = Constructions.get_reversed_type(os_model, layered_construction).eql?(2) ? Constructions.get_reversed_construction(os_model, layered_construction) : nil

      index = layer_index.to_i-1
      layer = layered_construction.getLayer(index)
      editable = layer.additionalProperties.getFeatureAsBoolean("editable")
      if !editable.empty? && editable.get then
        material_name = layer.additionalProperties.getFeatureAsString("material").get
        layered_construction.eraseLayer(index)
        layer.remove unless Constructions.get_num_materials(os_model, layer) > 0
        layer = Constructions.get_material(os_model, material_name, thickness.to_f)
        layered_construction.insertLayer(index, layer)

        unless reversed_construction.nil? then
          reversed_construction_name = reversed_construction.name.get.to_s
          reversed_construction.remove
          new_reversed_construction = Constructions.get_reversed_construction(os_model, layered_construction)
          new_reversed_construction.setName(reversed_construction_name)
          new_reversed_construction.additionalProperties.setFeature("reversed", true)
        end

        dialog.execute_script("sketchup.show_li('constructions', '#{construction_name}')")
      end
    end

    dialog.add_action_callback("sort_layers") do |action_context, construction_name, indices, source_layer|
      construction_name = Utilities.fix_name(construction_name)
      layered_construction = os_model.getLayeredConstructionByName(construction_name).get
      reversed_construction = Constructions.get_reversed_type(os_model, layered_construction).eql?(2) ? Constructions.get_reversed_construction(os_model, layered_construction) : nil

      layers = layered_construction.layers
      layered_construction.setLayers(indices.map do |layer_index| layered_construction.getLayer(layer_index.to_i-1) end)
      if source_layer > 0 then
        construction_with_internal_source = layered_construction.to_ConstructionWithInternalSource.get
        construction_with_internal_source.setSourcePresentAfterLayerNumber(source_layer)
        construction_with_internal_source.setTemperatureCalculationRequestedAfterLayerNumber(source_layer)
      end

      unless reversed_construction.nil? then
        reversed_construction_name = reversed_construction.name.get.to_s
        reversed_construction.remove
        new_reversed_construction = Constructions.get_reversed_construction(os_model, layered_construction)
        new_reversed_construction.setName(reversed_construction_name)
        new_reversed_construction.additionalProperties.setFeature("reversed", true)
      end

      dialog.execute_script("sketchup.show_li('constructions', '#{construction_name}')")
    end

    dialog.add_action_callback("replace_layer") do |action_context, construction_name, material_name, layer_index|
      script = []

      script << "sketchup.remove_layer('#{construction_name}', '#{layer_index}')"
      script << "sketchup.add_layer('#{construction_name}', '#{material_name}')"
      construction_name = Utilities.fix_name(construction_name)
      layered_construction = os_model.getLayeredConstructionByName(construction_name).get
      num_layers = layered_construction.layers.length
      indices = (num_layers-1).times.to_a.map do |index| index+1 end
      index = layer_index.to_i - 1
      indices.insert(index, num_layers)
      construction_with_internal_source = layered_construction.to_ConstructionWithInternalSource
      source_layer = construction_with_internal_source.empty? ? -1 : construction_with_internal_source.get.sourcePresentAfterLayerNumber
      script << "sketchup.sort_layers('#{construction_name}', [#{indices.join(", ")}], #{source_layer})"
      layer = layered_construction.getLayer(index)
      script << "sketchup.edit_layer('#{construction_name}', '#{Constructions.get_layer_thickness(layer)}', '#{layer_index}')"

      dialog.execute_script(script.join(";"))
    end

    dialog.add_action_callback("remove_layer") do |action_context, construction_name, layer_index|
      construction_name = Utilities.fix_name(construction_name)
      layered_construction = os_model.getLayeredConstructionByName(construction_name).get
      reversed_construction = Constructions.get_reversed_type(os_model, layered_construction).eql?(2) ? Constructions.get_reversed_construction(os_model, layered_construction) : nil

      index = layer_index.to_i - 1
      layer = layered_construction.getLayer(index)
      layered_construction.eraseLayer(index)
      layer.remove unless Constructions.get_num_materials(os_model, layer) > 0

      unless reversed_construction.nil? then
        reversed_construction_name = reversed_construction.name.get.to_s
        reversed_construction.remove
        new_reversed_construction = Constructions.get_reversed_construction(os_model, layered_construction)
        new_reversed_construction.setName(reversed_construction_name)
        new_reversed_construction.additionalProperties.setFeature("reversed", true)
      end

      dialog.execute_script("sketchup.show_li('constructions', '#{construction_name}')")
    end

    dialog.add_action_callback("add_edge_insulation") do |action_context, id, construction_name, material_name|
      construction_name = Utilities.fix_name(construction_name)
      edge_insulation = os_model.getFoundationKivaByName(construction_name).get
      insulation_material = nil

      eval("insulation_material = edge_insulation.#{Utilities.capitalize_all_but_first(id)}")
      unless insulation_material.empty? then
        insulation_material = insulation_material.get
        eval("edge_insulation.reset#{Utilities.capitalize_all(id)}")
        insulation_material.remove unless Constructions.get_num_materials(os_model, insulation_material) > 0
      end

      insulation_material = Constructions.get_material(os_model, material_name)
      eval("edge_insulation.set#{Utilities.capitalize_all(id)}(insulation_material)")

      dialog.execute_script("sketchup.show_li('constructions', '#{construction_name}')")
    end

    dialog.add_action_callback("edit_edge_insulation") do |action_context, id, construction_name, value|
      construction_name = Utilities.fix_name(construction_name)
      edge_insulation = os_model.getFoundationKivaByName(construction_name).get
      insulation_material = nil

      aux = id.split("_")
      temp = aux.pop
      aux << "material"
      eval("insulation_material = edge_insulation.#{Utilities.capitalize_all_but_first(aux.join("_"))}")
      unless insulation_material.empty? then
        insulation_material = insulation_material.get
        if temp.eql?("thickness") then
          material_name = insulation_material.additionalProperties.getFeatureAsString("material").get
          eval("edge_insulation.reset#{Utilities.capitalize_all(aux.join("_"))}")
          insulation_material.remove unless Constructions.get_num_materials(os_model, insulation_material) > 0
          insulation_material = Constructions.get_material(os_model, material_name, Utilities.convert(value.to_f, "cm", "m"))
          eval("edge_insulation.set#{Utilities.capitalize_all(aux.join("_"))}(insulation_material)")
        else
          aux[-1] = temp
          eval("edge_insulation.set#{Utilities.capitalize_all(aux.join("_"))}(#{value.to_f})")
        end
      end

      dialog.execute_script("sketchup.show_li('constructions', '#{construction_name}')")
    end

    dialog.add_action_callback("remove_edge_insulation") do |action_context, id, construction_name|
      construction_name = Utilities.fix_name(construction_name)
      edge_insulation = os_model.getFoundationKivaByName(construction_name).get
      insulation_material, other_material = nil, nil

      eval("insulation_material = edge_insulation.#{Utilities.capitalize_all_but_first(id)}")
      unless insulation_material.empty? then
        insulation_material = insulation_material.get
        eval("edge_insulation.reset#{Utilities.capitalize_all(id)}")
        insulation_material.remove unless Constructions.get_num_materials(os_model, insulation_material) > 0

        other_id = (["interior_horizontal_insulation_material", "exterior_vertical_insulation_material"]-[id])[0]
        eval("other_material = edge_insulation.#{Utilities.capitalize_all_but_first(other_id)}")
        edge_insulation.remove if other_material.empty?
      end

      dialog.execute_script("sketchup.show_li('constructions', '#{construction_name}')")
    end

    dialog.add_action_callback("replace_edge_insulation") do |action_context, id, construction_name, material_name, value|
      script = []

      script << "sketchup.add_edge_insulation('#{id}', '#{construction_name}', '#{material_name}')"
      script << "sketchup.edit_edge_insulation('#{id.gsub("_material", "_thickness")}', '#{construction_name}', '#{value.to_f}')"

      dialog.execute_script(script.join(";"))
    end

    dialog.add_action_callback("edit_material") do |action_context, id, material_name, value|
      script = []

      material_name = Utilities.fix_name(material_name)
      materials = Constructions.get_opaque_materials(os_model, material_name).map do |material| material.to_StandardOpaqueMaterial.get end

      aux = case id
      when "lambda"
        "setConductivity("
      when "rho"
        "setDensity("
      when "cp"
        "setSpecificHeat("
      when "mu"
        "additionalProperties.setFeature('mu', "
      end
      materials.each do |material| eval("material.#{aux}value.to_f)") end


      dialog.execute_script("sketchup.show_li('materials', '#{material_name}')")
    end

    dialog.add_action_callback("edit_glazing") do |action_context, id, glazing_name, value|
      script = []

      glazing_name = Utilities.fix_name(glazing_name)
      glazing = os_model.getSimpleGlazingByName(glazing_name).get
      aux = case id
      when "ufactor"
        "UFactor"
      when "shgc"
        "SolarHeatGainCoefficient"
      when "vlt"
        "VisibleTransmittance"
      end
      eval("glazing.set#{aux}(value)")

      dialog.execute_script("sketchup.show_li('glazings', '#{glazing_name}')")
    end

    dialog.add_action_callback("edit_standards_information") do |action_context, id, glazing_name, option|
      glazing_name = Utilities.fix_name(glazing_name)
      standards_information = os_model.getLayeredConstructionByName(glazing_name).get.standardsInformation
      eval("standards_information.set#{Utilities.capitalize_all(id)}(option)")
    end

    dialog.add_action_callback("edit_frame") do |action_context, id, frame_name, value|
      script = []

      frame_name = Utilities.fix_name(frame_name)
      frame = os_model.getWindowPropertyFrameAndDividerByName(frame_name).get
      case id
      when "frame_width"
        frame.setFrameWidth(Utilities.convert(value, "cm", "m"))

      when "frame_conductance"
        frame.setFrameConductance(value)

      when "frame_setback"
        frame.setOutsideRevealDepth(Utilities.convert(value, "cm", "m"))

      when "frame_colour"
        value = value.to_f
        if value < 0 then
          frame.additionalProperties.resetFeature("frame_reflectance")
        else
          frame.additionalProperties.setFeature("frame_reflectance", value)
        end
      end

      case id
      when "frame_colour", "frame_reflectance"
        frame.setFrameSolarAbsorptance(1 - value)
        frame.setFrameVisibleAbsorptance(1 - value)
      end

      dialog.execute_script("sketchup.show_li('frames', '#{frame_name}')")
    end

    dialog.add_action_callback("edit_thermal_bridge") do |action_context, id, thermal_bridge_name, value|
      script = []

      thermal_bridge_name = Utilities.fix_name(thermal_bridge_name)
      thermal_bridge = os_model.getMasslessOpaqueMaterialByName(thermal_bridge_name).get
      case id
      when "thermal_bridge_type"
        thermal_bridge_type = thermal_bridge.additionalProperties.getFeatureAsString("thermal_bridge_type").get
        thermal_bridge.additionalProperties.setFeature("thermal_bridge_type", value)
        thermal_bridge.setThermalResistance(1.0 / ThermalBridges.get_default_psi) if (1.0 / thermal_bridge.thermalResistance - ThermalBridges.get_default_psi).abs < 1e-6

      when "thermal_bridge_psi"
        thermal_bridge.setThermalResistance(1.0 / value)
      end

      dialog.execute_script("sketchup.show_li('thermal_bridges', '#{thermal_bridge_name}')")
    end

    def self.select_edges_thermal_bridges(edges, new_groups, su2os, thermal_bridge_type)
      return edges.inject([]) do |sum, edge| sum + SketchUp.get_edge_surfaces(edge, new_groups, su2os) end.map do |planar_surfaces|
        next unless planar_surfaces.first.space.get.partofTotalFloorArea

        exterior_walls, others = planar_surfaces.sort_by do |planar_surface|
          planar_surface.name.get.to_s
        end.partition do |planar_surface|
          !planar_surface.to_Surface.empty? && planar_surface.surfaceType.eql?("Wall") && planar_surface.outsideBoundaryCondition.eql?("Outdoors")
        end

        case exterior_walls.length
        when 1
          other = others.first
          if other.to_Surface.empty? then
            case thermal_bridge_type
            when "hueco", "capialzado"
              sub_surface_type = other.subSurfaceType
              next unless (sub_surface_type.end_with?("Window") || sub_surface_type.eql?("GlassDoor"))

            else
              next
            end
          else
            surface_type, outsise_boundary_condition = other.surfaceType, other.outsideBoundaryCondition
            case thermal_bridge_type
            when "frente_forjado"
              next unless surface_type.eql?("Floor") && outsise_boundary_condition.eql?("Surface")

            when "contorno_cubierta"
              next unless surface_type.eql?("RoofCeiling") && outsise_boundary_condition.eql?("Outdoors")

            when "forjado_aire"
              next unless surface_type.eql?("Floor") && outsise_boundary_condition.eql?("Outdoors")

            when "contorno_de_solera"
              next unless surface_type.eql?("Floor") && outsise_boundary_condition.eql?("Ground")

            else
              next
            end
          end

        when 2
          aux = exterior_walls.first.outwardNormal.dot(exterior_walls.last.centroid - exterior_walls.first.centroid)
          case thermal_bridge_type
          when "pilares"
            next unless aux.abs < 1e-6

          when "esquina"
            case id
            when "thermal_bridges"
              next unless aux < 1e-6

            else
              case li[-1].to_i
              when 2
                next unless aux < 1e-6

              when 1
                next unless aux > 1e-6
              end
            end

          else
            next
          end

        else
          next
        end

        exterior_walls + others
      end.compact
    end

    def self.assign_surface_planar_surface(os_model, planar_surface)
      script = []

      surface = planar_surface.to_Surface
      adjacent_planar_surface = if surface.empty? then
        planar_surface.to_SubSurface.get.adjacentSubSurface.get
      else
        surface.get.adjacentSurface.get
      end

      if planar_surface.isConstructionDefaulted then
        adjacent_planar_surface.resetConstruction
      else
        construction = planar_surface.construction.get

        reversed_type = Constructions.get_reversed_type(os_model, construction)
        adjacent_construction = if reversed_type.eql?(0) then
          construction
        else
          reversed_construction = Constructions.get_reversed_construction(os_model, construction)
          if reversed_type.eql?(1) then
            reversed_construction.additionalProperties.setFeature("interface", true)
            reversed_construction.additionalProperties.setFeature("reversed", true)
            script << "unselect_left()"
            script << "sketchup.show_li('constructions', '#{construction.name.get.to_s}')"
          end
          reversed_construction
        end

        adjacent_planar_surface.setConstruction(adjacent_construction)
      end

      return script
    end

    def self.select_spaces_thermal_bridges(spaces, thermal_bridge_type, group)
      return spaces.select do |space| space.partofTotalFloorArea end.inject([]) do |sum, space|
        temp = []

        surfaces = space.surfaces.sort_by do |surface| surface.name.get.to_s end
        exterior_walls = surfaces.select do |surface| surface.surfaceType.eql?("Wall") && surface.outsideBoundaryCondition.eql?("Outdoors") end
        exterior_walls.each_with_index do |exterior_wall, i|
          exterior_wall.subSurfaces.each do |sub_surface|
            case thermal_bridge_type
            when "hueco", "capialzado"
              sub_surface_type = sub_surface.subSurfaceType
              next unless (sub_surface_type.end_with?("Window") || sub_surface_type.eql?("GlassDoor"))

            else
              next
            end

            temp << [exterior_wall, sub_surface]
          end

          (surfaces - exterior_walls).each do |surface|
            next if Geometry.get_length(exterior_wall.vertices, surface.vertices) < 1e-6

            surface_type, outsise_boundary_condition = surface.surfaceType, surface.outsideBoundaryCondition
            case thermal_bridge_type
            when "frente_forjado"
              next unless surface_type.eql?("Floor") && outsise_boundary_condition.eql?("Surface")

            when "contorno_cubierta"
              next unless surface_type.eql?("RoofCeiling") && outsise_boundary_condition.eql?("Outdoors")

            when "forjado_aire"
              next unless surface_type.eql?("Floor") && outsise_boundary_condition.eql?("Outdoors")

            when "contorno_de_solera"
              next unless surface_type.eql?("Floor") && outsise_boundary_condition.eql?("Ground")

            else
              next
            end

            temp << [exterior_wall, surface]
          end

          exterior_walls[i+1..-1].each do |surface|
            next if Geometry.get_length(exterior_wall.vertices, surface.vertices) < 1e-6

            aux = exterior_wall.outwardNormal.dot(surface.centroid - exterior_wall.centroid)
            case thermal_bridge_type
            when "pilares"
              next unless aux.abs < 1e-6

            when "esquina"
              case group
              when 0, 2
                next unless aux < 1e-6

              when 1
                next unless aux > 1e-6
              end

            else
              next
            end

            temp << [exterior_wall, surface]
          end
        end

        sum + temp
      end
    end

    dialog.add_action_callback("assign") do |action_context, input, id, li|
      script = []

      selection = su_model.selection
      unless input.eql?("materials") then
        thermal_bridge_type = case input
        when "thermal_bridges"
          id.eql?(input) ? os_model.getMasslessOpaqueMaterialByName(li).get.additionalProperties.getFeatureAsString("thermal_bridge_type").get : id

        else
          nil
        end

        spaces, surfaces, sub_surfaces, edges_surfaces = if selection.empty? then
          unless UI.messagebox("Assign to all?", MB_YESNO).eql?(IDYES) then
            [[], [], [], []]
          else
            case input
            when "constructions"
              [[], os_model.getSurfaces, [], []]

            when "windows"
              [[], [], os_model.getSubSurfaces, []]

            when "construction_sets", "thermal_bridges"
              [os_model.getSpaces, [], [], []]
            end
          end
        else
          planar_surfaces = SketchUp.get_selected_planar_surfaces(os_model)
          [
            selection.grep(Sketchup::Group).map do |group| SketchUp.get_space(group, os2su) end.compact,
            planar_surfaces.select do |planar_surface| planar_surface.to_SubSurface.empty? end,
            planar_surfaces.select do |planar_surface| planar_surface.to_Surface.empty? end,
            if thermal_bridge_type.nil? then
              []
            else
              self.select_edges_thermal_bridges(selection.grep(Sketchup::Edge), new_groups, su2os, thermal_bridge_type)
            end
          ]
        end

        case id
        when "construction_sets"
          construction_set = os_model.getDefaultConstructionSetByName(li).get
          spaces.each do |space| space.setDefaultConstructionSet(construction_set) end

        when "constructions", "glazings"
          construction = os_model.getLayeredConstructionByName(li).get
          case id
          when "constructions"
            spaces.inject(surfaces) do |sum, space| sum + space.surfaces end

          when "glazings"
            spaces.inject(sub_surfaces) do |sum, space| sum + space.surfaces.inject([]) do |sum, surface| sum + surface.subSurfaces end end
          end.each do |planar_surface|
            planar_surface.setConstruction(construction)
            next unless planar_surface.outsideBoundaryCondition.eql?("Surface")

            script += self.assign_surface_planar_surface(os_model, planar_surface)
          end

        when "frames"
          frame = os_model.getWindowPropertyFrameAndDividerByName(li).get
          spaces.inject(sub_surfaces) do |sum, space| sum + space.surfaces.inject([]) do |sum, surface| sum + surface.subSurfaces end end.select do |sub_surface|
            sub_surface_type = sub_surface.subSurfaceType
            centroid = sub_surface.centroid
            vertices = sub_surface.vertices.map do |vertex| (vertex - centroid).length end
            sub_surface.outsideBoundaryCondition.eql?("Outdoors") && (sub_surface_type.end_with?("Window") || sub_surface_type.eql?("GlassDoor")) && (vertices.length.eql?(4) || vertices.uniq.length.eql?(1))
          end.each do |sub_surface|
            sub_surface.setWindowPropertyFrameAndDivider(frame)
          end

        else
          group = id.eql?("thermal_bridges") ? 0 : li[-1].to_i

          (edges_surfaces + self.select_spaces_thermal_bridges(spaces, thermal_bridge_type, group)).each do |exterior_wall, other|
            thermal_bridges = exterior_wall.additionalProperties.getFeatureAsString("thermal_bridges")
            thermal_bridges = thermal_bridges.empty? ? zc_thermal_bridge_types.map do |key| [key, (ThermalBridges.get_ngroups(key) + 1).times.map do |x| [] end] end.to_h : JSON.parse(thermal_bridges.get)

            other_name = other.name.get.to_s
            thermal_bridges[thermal_bridge_type].each do |others| others.delete(other_name) end

            if group.eql?(0) then
              exterior_wall_name = exterior_wall.name.get.to_s
              os_model.getMasslessOpaqueMaterials.each do |thermal_bridge|
                aux = thermal_bridge.additionalProperties.getFeatureAsString("thermal_bridge_type")
                next if aux.empty?
                next unless thermal_bridge_type.eql?(aux.get)
                exterior_wall2others = thermal_bridge.additionalProperties.getFeatureAsString("exterior_wall2others")
                next if exterior_wall2others.empty?

                exterior_wall2others = JSON.parse(exterior_wall2others.get)
                (exterior_wall2others[exterior_wall_name] || []).each do |value| value.delete(other_name) end

                thermal_bridge.additionalProperties.setFeature("exterior_wall2others", exterior_wall2others.to_json)
              end
              thermal_bridge = os_model.getMasslessOpaqueMaterialByName(li).get
              exterior_wall2others = JSON.parse(thermal_bridge.additionalProperties.getFeatureAsString("exterior_wall2others").get)
              exterior_wall2others[exterior_wall_name] = (exterior_wall2others[exterior_wall_name] || []) + [other_name]
              thermal_bridge.additionalProperties.setFeature("exterior_wall2others", exterior_wall2others.to_json)
            end

            thermal_bridges[thermal_bridge_type][group] << other_name
            exterior_wall.additionalProperties.setFeature("thermal_bridges", thermal_bridges.to_json)
          end
        end

        script << "sketchup.show_li('#{id}', '#{li}')"
      end

      selection.grep(Sketchup::Edge).each do |edge| edge.erase! end
      selection.clear

      dialog.execute_script(script.join(";"))
    end

    def self.remove_thermal_bridge(os_model, exterior_wall_name, other_name, thermal_bridge_type)
      os_model.getMasslessOpaqueMaterials.each do |thermal_bridge|
        aux = thermal_bridge.additionalProperties.getFeatureAsString("thermal_bridge_type")
        next if aux.empty?
        next unless aux.get.eql?(thermal_bridge_type)
        exterior_wall2others = thermal_bridge.additionalProperties.getFeatureAsString("exterior_wall2others")
        next if exterior_wall2others.empty?

        exterior_wall2others = JSON.parse(exterior_wall2others.get)
        next unless exterior_wall2others[exterior_wall_name].include?(other_name)
        exterior_wall2others[exterior_wall_name].delete(other_name)
        exterior_wall2others.delete(exterior_wall_name) if exterior_wall2others[exterior_wall_name].empty?

        thermal_bridge.additionalProperties.setFeature("exterior_wall2others", exterior_wall2others.to_json)
        break
      end
    end

    dialog.add_action_callback("remove") do |action_context, input, id, li|
      script = []

      selection = su_model.selection
      unless input.eql?("materials") then
        thermal_bridge_type = case input
        when "thermal_bridges"
          id.eql?(input) ? os_model.getMasslessOpaqueMaterialByName(li).get.additionalProperties.getFeatureAsString("thermal_bridge_type").get : id

        else
          nil
        end

        spaces, surfaces, sub_surfaces, edges_surfaces = if selection.empty? then
          unless UI.messagebox("Remove all?", MB_YESNO).eql?(IDYES) then
            [[], [], [], []]
          else
            case input
            when "constructions"
              [[], os_model.getSurfaces, [], []]

            when "windows"
              [[], [], os_model.getSubSurfaces, []]

            when "construction_sets", "thermal_bridges"
              [os_model.getSpaces, [], [], []]
            end
          end
        else
          planar_surfaces = SketchUp.get_selected_planar_surfaces(os_model)
          [
            selection.grep(Sketchup::Group).map do |group| SketchUp.get_space(group, os2su) end.compact,
            planar_surfaces.select do |planar_surface| planar_surface.to_SubSurface.empty? end,
            planar_surfaces.select do |planar_surface| planar_surface.to_Surface.empty? end,
            self.select_edges_thermal_bridges(selection.grep(Sketchup::Edge), new_groups, su2os, thermal_bridge_type)
          ]
        end

        case input
        when "construction_sets"
          spaces.each do |space| space.resetDefaultConstructionSet end

        when "constructions", "windows"
          case input
          when "constructions"
            spaces.inject(surfaces) do |sum, space| sum + space.surfaces end

          when "windows"
            spaces.inject(sub_surfaces) do |sum, space| sum + space.surfaces.inject([]) do |sum, surface| sum + surface.subSurfaces end end
          end

          case id
          when "constructions", "glazings"
            (surfaces + sub_surfaces).each do |planar_surface|
              planar_surface.resetConstruction
              next unless planar_surface.outsideBoundaryCondition.eql?("Surface")

              script += self.assign_surface_planar_surface(os_model, planar_surface)
            end

          when "frames"
            sub_surfaces.each do |sub_surface| sub_surface.resetWindowPropertyFrameAndDivider end
          end

        when "thermal_bridges"
          group = id.eql?("thermal_bridges") ? 0 : li[-1].to_i

          (edges_surfaces + self.select_spaces_thermal_bridges(spaces, thermal_bridge_type, group)).each do |exterior_wall, other|
            thermal_bridges = exterior_wall.additionalProperties.getFeatureAsString("thermal_bridges")
            next if thermal_bridges.empty?

            exterior_wall_name, other_name = exterior_wall.name.get.to_s, other.name.get.to_s
            thermal_bridges = JSON.parse(thermal_bridges.get)
            thermal_bridges[thermal_bridge_type] = thermal_bridges[thermal_bridge_type].each_with_index.map do |others, index|
              if others.include?(other_name) then
                self.remove_thermal_bridge(os_model, exterior_wall_name, other_name, thermal_bridge_type) if index.eql?(0)
                others.delete(other_name)
              end

              others
            end

            if thermal_bridges.find do |thermal_bridge_type, value| !value.find do |others| !others.empty? end.nil? end.nil? then
              exterior_wall.additionalProperties.resetFeature("thermal_bridges")
            else
              exterior_wall.additionalProperties.setFeature("thermal_bridges", thermal_bridges.to_json)
            end
          end
        end

        script << "sketchup.show_li('#{id}', '#{li}')"
      end

      selection.grep(Sketchup::Edge).each do |edge| edge.erase! end
      selection.clear

      dialog.execute_script(script.join(";"))
    end

    thermal_bridges_psis = []

    def self.get_mirror_h_color(planar_surface, adjacent_planar_surface, os_model)
      construction = planar_surface.construction
      adjacent_construction = adjacent_planar_surface.construction

      if construction.empty? || adjacent_construction.empty? then
        return 0
      else
        construction = construction.get
        adjacent_construction = adjacent_construction.get

        case Constructions.get_reversed_type(os_model, construction)
        when 0
          return 0 unless construction.eql?(adjacent_construction)
        when 1
          return ( construction.eql?(adjacent_construction) ? 60 : 0 )
        else
          if construction.eql?(adjacent_construction) then
            return 60
          elsif !Constructions.get_reversed_construction(os_model, construction).eql?(adjacent_construction) then
            return 0
          end
        end
      end

      return 120
    end

    dialog.add_action_callback("compute_k_global") do |action_context, output|
      script = []

      if render.eql?("w_k") then
        su_model.rendering_options["EdgeColorMode"] = 0
        su_model.rendering_options["DrawDepthQue"] = 1
        su_model.rendering_options["DepthQueWidth"] = 10
      end

      ["thead", "tbody"].each do |value|
        script << "var #{value} = document.querySelectorAll('#results #{value}')[0]"
        script << "$('#results #{value} tr').remove()"
      end

      script << "var header_names = thead.insertRow(0)"
      script << "var header_units = thead.insertRow(1)"
      case output
      when "opaques_u"
        {
          "Surface" => "text",
          "Type" => "text",
          "Boundary condition" => "text",
          "Area [m<sup>2</sup>]" => "number",
          "U [W/m<sup>2</sup> K]" => "number",
          "A·U [W/K]" => "number"
        }

      when "windows_u"
        {
          "Sub Surface" => "text",
          "Boundary condition" => "text",
          "A<sub>g</sub> [m<sup>2</sup>]" => "number",
          "U<sub>g</sub> [W/m<sup>2</sup> K]" => "number",
          "A<sub>f</sub> [m<sup>2</sup>]" => "number",
          "U<sub>f</sub> [W/m<sup>2</sup> K]" => "number",
          "l<sub>g</sub> [m]" => "number",
          "&Psi;<sub>g</sub> [W/m K]" => "number",
          "U [W/m<sup>2</sup> K]" => "number",
          "A·U [W/K]" => "number"
        }

      when "thermal_bridges_psi"
        {
          "Space" => "text",
          "Type" => "text",
          "Length [m]" => "number",
          "&Psi; [W/m K]" => "number",
          "l·&Psi; [W/K]" => "number"
        }

      else
        {}
      end.each_with_index do |(text, type), index|
        script << "var cell = document.createElement('th')"
        script << "cell.classList.add('#{type}')"
        case type
        when "text"
          script << "cell.innerHTML = '#{text}'"
          script << "cell.rowSpan = '2'"

        when "number"
          script << "cell.innerHTML = '#{text.split(" [").first}'"
        end
        script << "header_names.appendChild(cell)"
      end.each_with_index do |(text, type), index|
        script << "var cell = document.createElement('th')"
        script << "cell.classList.add('#{type}')"
        case type
        when "text"
          script << "cell.style.display = 'none'"

        when "number"
          script << "cell.innerHTML = '#{"[" + text.split(" [").last}'"
        end
        script << "header_units.appendChild(cell)"
      end

      opaques_us, windows_us, thermal_bridges_psis = [], [], []

      au = 0.0
      os_model.getSpaces.each do |space|
        next unless space.partofTotalFloorArea

        space_thermal_bridges = cte_thermal_bridge_types.map do |key| [key, {"length" => 0.0, "au" => 0.0}] end.to_h
        surfaces = space.surfaces
        air_walls = surfaces.select do |surface| surface.isAirWall end
        space_transformation = space.transformation

        surfaces.each do |surface|
          surface_name = surface.name.get.to_s
          boundary_condition = surface.outsideBoundaryCondition
          adjacent_space = nil

          surface_u_factor = case boundary_condition
          when "Outdoors"
            Constructions.get_outdoors_u_factor(surface)
          when "Surface"
            adjacent_space = surface.adjacentSurface.get.space.get
            adjacent_space.partofTotalFloorArea ? nil : Constructions.get_unconditioned_u_factor(surface, adjacent_space)
          when "Ground"
            Constructions.get_ground_u_factor(surface, space, ground_level_plane, os_model)
          end
          next if surface_u_factor.nil?

          surface_area = surface.netArea
          surface_type = surface.surfaceType
          outward_normal = surface.outwardNormal
          case boundary_condition
          when "Outdoors"
            surface.subSurfaces.each do |sub_surface|
              sub_surface_area, sub_surface_u_factor, frame_area, frame_u_factor, perimeter, psi_value = Constructions.get_outdoors_window_thermal_properties(sub_surface)

              u_lim = u_lims[3]
              unless frame_area.nil? then
                surface_area -= frame_area

                sub_surface_au = sub_surface_area * sub_surface_u_factor + frame_area * frame_u_factor + perimeter * psi_value
                overall_u = sub_surface_au / (sub_surface_area + frame_area)
                windows_us << [
                  [sub_surface.name.get.to_s, -1],
                  [boundary_condition, -1],
                  [sub_surface_area, 1],
                  [sub_surface_u_factor, 1],
                  [frame_area, 2],
                  [frame_u_factor, 1],
                  [perimeter, 1],
                  [psi_value, 2],
                  [overall_u, 1, u_lim],
                  [sub_surface_au, 1]
                ]

                au += sub_surface_au
              else
                sub_surface_au = sub_surface_area * sub_surface_u_factor

                windows_us << [
                  [sub_surface.name.get.to_s, -1],
                  [boundary_condition, -1],
                  [sub_surface_area, 1],
                  [sub_surface_u_factor, 1],
                  ["-", -1],
                  ["-", -1],
                  ["-", -1],
                  ["-", -1],
                  [sub_surface_u_factor, 1, u_lim],
                  [sub_surface_au, 1]
                ]

                au += sub_surface_au
              end
            end

            while true do
              break unless surface_type.eql?("Wall")

              thermal_bridges = surface.additionalProperties.getFeatureAsString("thermal_bridges")
              break if thermal_bridges.empty?

              surface_transformation = OpenStudio::Transformation.alignFace(surface.vertices)
              thermal_bridges = JSON.parse(thermal_bridges.get)
              dintel_psi = {}
              zc_thermal_bridge_types.each do |thermal_bridge_type|
                thermal_bridges[thermal_bridge_type].each_with_index do |others, group|
                  others.each do |other|
                    case thermal_bridge_type
                    when "hueco", "capialzado"
                      sub_surface = os_model.getSubSurfaceByName(other).get

                      sub_surface_area, sub_surface_u_factor, frame_area, frame_u_factor, perimeter, psi_value = Constructions.get_outdoors_window_thermal_properties(sub_surface)
                      frame_u_factor = frame_u_factor || sub_surface_u_factor
                      frame_width = frame_area.nil? ? 0.0 : (Math.sqrt(perimeter * perimeter + 16.0 * frame_area) - perimeter) / 8.0

                      os2su[sub_surface].edges.each do |edge|
                        position = nil
                        points = ["start", "end"].map do |value|
                          eval("position = edge.#{value}.position")
                          surface_transformation.inverse * space_transformation.inverse * OpenStudio::Point3d.new(position.x.to_m, position.y.to_m, position.z.to_m)
                        end
                        edge_vector = points.last - points.first
                        edge_vector.normalize
                        edge_normal = edge_vector.cross(OpenStudio::Vector3d.new(0, 0, 1))

                        edge_length = edge.length.to_m
                        if frame_width > 1e-6 then
                          edge_normal.setLength(frame_width)
                          translation = OpenStudio::createTranslation(edge_normal)

                          air_walls.each do |air_wall| edge_length -= Geometry.get_length(surface_transformation * translation * points, air_wall.vertices) end
                          edge_normal.normalize
                        end
                        next unless edge_length > 1e-6

                        angle = Utilities.convert(Math.acos(OpenStudio::Vector3d.new(0, 1, 0).dot(edge_normal)), "rad", "deg")
                        cte_type = if angle < 45 then
                          case thermal_bridge_type
                          when "hueco"
                            "dintel"

                          when "capialzado"
                            thermal_bridge_type
                          end
                        elsif angle > 135 then
                          next if thermal_bridge_type.eql?("capialzado")

                          "alfeizar"
                        else
                          next if thermal_bridge_type.eql?("capialzado")

                          "jamba"
                        end

                        psi = if group.eql?(0) then
                          self.get_input_psi(thermal_bridge_type, surface_name, other)
                        else
                          ThermalBridges.get_cte_psi(cte_type, group, surface_u_factor, frame_u_factor)
                        end

                        case render
                        when "w_k"
                          h = [1.0 - edge_length * psi / w_k_lim, 0.0].max * 120

                          color = Sketchup::Color.new
                          OpenStudio::set_hsba(color, [h, 100, 100, 1.0])
                          SketchUp.set_material(edge, color)
                        end

                        space_thermal_bridges[cte_type]["length"] += edge_length
                        space_thermal_bridges[cte_type]["au"] += edge_length * psi
                        next unless !dintel_psi[other].nil? && cte_type.eql?("capialzado")

                        space_thermal_bridges["dintel"]["length"] -= edge_length
                        space_thermal_bridges["dintel"]["au"] -= edge_length * dintel_psi[other]
                      end
                    else
                      other_surface = os_model.getSurfaceByName(other).get

                      cte_other = case thermal_bridge_type
                      when "pilares", "frente_forjado"
                        Utilities.convert(Constructions.get_construction_thickness(other_surface), "m", "cm")

                      when "contorno_cubierta", "esquina", "forjado_aire"
                        Constructions.get_outdoors_u_factor(other_surface)

                      when "contorno_de_solera"
                        Constructions.get_ground_u_factor(other_surface, space, ground_level_plane, os_model)
                      end

                      length = Geometry.get_length(surface.vertices, other_surface.vertices)
                      psi = if group.eql?(0) then
                        Constructions.get_input_psi(thermal_bridge_type, surface_name, other)
                      else
                        ThermalBridges.get_cte_psi(thermal_bridge_type, group, surface_u_factor, cte_other)
                      end

                      case render
                      when "w_k"
                        h = [1.0 - length * psi / w_k_lim, 0.0].max * 120

                        face = os2su[surface]
                        os2su[other_surface].edges.each do |edge|
                          next unless edge.used_by?(face)

                          color = Sketchup::Color.new
                          OpenStudio::set_hsba(color, [h, 100, 100, 1.0])
                          SketchUp.set_material(edge, color)
                        end
                      end

                      space_thermal_bridges[thermal_bridge_type]["length"] += length
                      space_thermal_bridges[thermal_bridge_type]["au"] += length * psi
                    end
                  end
                end
              end

              break
            end

          when "Surface"
            surface.subSurfaces.each do |sub_surface|
              sub_surface_area = sub_surface.grossArea
              sub_surface_u_factor = Constructions.get_unconditioned_u_factor(sub_surface, adjacent_space)

              sub_surface_au = sub_surface_area * sub_surface_u_factor
              windows_us << [
                [sub_surface.name.get.to_s, -1],
                [boundary_condition, -1],
                [sub_surface_area, 1],
                [sub_surface_u_factor, 1],
                ["-", -1],
                ["-", -1],
                ["-", -1],
                ["-", -1],
                [sub_surface_u_factor, 1, u_lims[3]],
                [sub_surface_au, 1]
              ]

              au += sub_surface_au
            end
          end

          u_lim = case boundary_condition
          when "Outdoors"
            u_lims[ surface_type.eql?("RoofCeiling") ? 1 : 0 ]

          else
            u_lims[2]
          end
          
          surface_area = [surface_area, 0.0].max
          surface_au = surface_area * surface_u_factor
          opaques_us << [
            [surface_name, -1],
            [surface_type, -1],
            [boundary_condition, -1],
            [surface_area, 1],
            [surface_u_factor, 2, u_lim],
            [surface_au, 1]
          ]

          au += surface_au
        end

        space_thermal_bridges.each do |thermal_bridge_type, thermal_bridge|
          length = thermal_bridge["length"]
          next if length < 1e-6

          thermal_bridge_au = thermal_bridge["au"]
          thermal_bridges_psis << [
            [space.name.get.to_s, -1],
            [thermal_bridge_type.gsub("_", " ").capitalize, -1],
            [length, 1],
            [thermal_bridge_au / length, 2],
            [thermal_bridge_au, 2]
          ]

          au += thermal_bridge_au
        end
      end

      case render
      when "w_k", "u_limit"
        opaques_us.each do |row|
          h = case render
          when "w_k"
            [1.0 - row[-1].first / w_k_lim, 0.0].max * 120

          when "u_limit"
            [1.0 - row[-2].first  / row[-1].last, 0.0].max * 120
          end

          color = Sketchup::Color.new
          OpenStudio::set_hsba(color, [h, 100, 100, 1.0])

          surface = os_model.getSurfaceByName(row[0].first).get
          SketchUp.set_material(os2su[surface], color)

          adjacent_surface = surface.adjacentSurface
          next if adjacent_surface.empty?

          SketchUp.set_material(os2su[adjacent_surface.get], color)
        end

        windows_us.each do |row|
          h = case render
          when "w_k"
            [1.0 - row[-1].first / w_k_lim, 0.0].max * 120

          when "u_limit"
            [1.0 - row[-2].first  / u_lims[3], 0.0].max * 120
          end

          color = Sketchup::Color.new
          OpenStudio::set_hsba(color, [h, 100, 100, 1.0])

          sub_surface = os_model.getSubSurfaceByName(row[0].first).get
          SketchUp.set_material(os2su[sub_surface], color)

          adjacent_sub_surface = sub_surface.adjacentSubSurface
          next if adjacent_sub_surface.empty?

          SketchUp.set_material(os2su[adjacent_sub_surface.get], color)
        end
      end

      os_model.getSurfaces.each do |surface|
        next unless surface.outsideBoundaryCondition.eql?("Surface")

        surface_name = surface.name.get.to_s
        adjacent_surface = surface.adjacentSurface.get
        next if adjacent_surface.name.get.to_s < surface_name

        case render
        when "mirror"
          ([surface] + surface.subSurfaces).each_with_index do |planar_surface, index|
            face = os2su[planar_surface]
            adjacent_planar_surface = index > 0 ? planar_surface.adjacentSubSurface.get : adjacent_surface
            adjacent_face = os2su[adjacent_planar_surface]

            color = Sketchup::Color.new
            h = self.get_mirror_h_color(planar_surface, adjacent_planar_surface, os_model)
            OpenStudio::set_hsba(color, [h, 100, 100, 1.0])
            SketchUp.set_material(face, color)
            SketchUp.set_material(adjacent_face, color)
          end
        end
      end

      # opaques_us = opaques_us.sort_by do |row|
        # aux = row[-1]
        # aux.first / aux.last
      # end.reverse

      (case output
      when "opaques_u"
        opaques_us

      when "windows_u"
        windows_us

      when "thermal_bridges_psi"
        thermal_bridges_psis
      end || []).sort_by do |row|
        row.last.first || -1
      end.reverse.each_with_index do |row, i|
        script << "var row = tbody.insertRow(#{i})"
        row.each_with_index do |(value, round, limit), j|
          script << "var cell = row.insertCell(#{j})"
          if round < 0 then
            script << "cell.innerHTML = '#{value}'"
            if value.eql?("-") then
              script << "cell.classList.add('number')"
            else
              script << "cell.classList.add('text')"
            end
          else
            if value.nil? then
              script << "cell.innerHTML = '-'"
            elsif value > 1e5 then
              script << "cell.innerHTML = 'Inf'"
              script << "cell.style.color = 'red'" unless limit.nil?
            else
              script << "cell.innerHTML = parseFloat(#{value}).toFixed(#{round})"
              script << "cell.style.color = 'red'" unless limit.nil? || value < limit
            end
            script << "cell.classList.add('number')"
          end
        end
      end

      script << "var k_global = document.querySelectorAll('#kglobal input')[0]"
      script << "k_global.value = parseFloat(#{au / area_int}).toFixed(2)"
      script << "k_global.style.color = '#{ au > au_lim ? "red" : nil }'"

      dialog.execute_script(script.join(";"))
    end

    dialog.add_action_callback("select_object") do |action_context, output, name|
      selection = su_model.selection
      selection.clear

      object = case output
      when "opaques_u", "windows_u"
        planar_surface = case output
        when "opaques_u"
          os_model.getSurfaceByName(name).get

        when "windows_u"
          os_model.getSubSurfaceByName(name).get
        end

        face = os2su[planar_surface]
        selection.add(face)
        face.edges.each do |edge| selection.add(edge) end
      when "thermal_bridges_psi"
        space = os_model.getSpaceByName(name).get

        face = os2su[space.surfaces[0]]
        new_groups.each do |group|
          next unless group.entities.include?(face)

          selection.add(group)
          break
        end
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
      su_model.rendering_options["EdgeColorMode"] = 1
      su_model.rendering_options["DrawDepthQue"] = 0
      new_groups.each do |group| group.erase! end

      if ok then
        os_model.getSpaces.each do |space| space.drawing_interface.entity.hidden = false end
        os_model.getShadingSurfaceGroups.each do |group| group.drawing_interface.entity.locked = false end

        cte_materials_hash.values.each do |materials| materials.values.each(&:remove) end
        air_gap.remove

        layers = []
        os_model.getLayeredConstructions.select do |layered_construction|
          interface = layered_construction.additionalProperties.getFeatureAsBoolean("interface")
          !interface.empty? && interface.get
        end.each do |layered_construction|
          edge_insulation = os_model.getFoundationKivaByName(Utilities.fix_name(layered_construction.name.get.to_s))
          next if edge_insulation.empty?

          edge_insulation, insulation_material = edge_insulation.get, nil
          [["interior", "horizontal", "width"], ["exterior", "vertical", "depth"]].each do |type|
            eval("insulation_material = edge_insulation.#{type[0]}#{type[1].capitalize}InsulationMaterial")
            next if insulation_material.empty?

            layer = insulation_material.get
            layers << layer
          end
        end
        layers.uniq.each do |layer|
          material = layer.additionalProperties.getFeatureAsString("material")
          next if material.empty?
          material = material.get
          material += " [thk #{Utilities.convert(Constructions.get_layer_thickness(layer), "m", "cm").round(1)}cm]" if layer.additionalProperties.getFeatureAsBoolean("editable").get
          layer.setName(material)
        end

        thermal_bridges_psis.map do |row|
          row.map do |cell| cell.first end
        end.each do |space_name, thermal_bridge_type, length, psi, au|
          ThermalBridges.add_surface(os_model, space_name, thermal_bridge_type.gsub(" ", "_").downcase, length, psi)
        end

        os_model.getAdditionalPropertiess.each do |additional_properties| additional_properties.modelObject.removeAdditionalProperties if additional_properties.featureNames.empty? end

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

end