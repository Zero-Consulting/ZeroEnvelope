#
#--
# geom2d - 2D Geometric Objects and Algorithms
# Copyright (C) 2018 Thomas Leitner <t_leitner@gmx.at>
#
# This software may be modified and distributed under the terms
# of the MIT license.  See the LICENSE file for details.
#++

require "#{File.dirname(__FILE__)}/clipper.so"

module Geom2D
  module Algorithms

    # Performs intersection, union, difference and xor operations on Geom2D::PolygonSet objects.
    #
    # The entry method is PolygonOperation.run.
    #
    # The algorithm is described in the paper "A simple algorithm for Boolean operations on
    # polygons" by Martinez et al (see http://dl.acm.org/citation.cfm?id=2494701). This
    # implementation is based on the public domain code from
    # http://www4.ujaen.es/~fmartin/bool_op.html, which is the original implementation from the
    # authors of the paper.
    class PolygonOperation      
      
      # Performs the given operation (:union, :intersection, :difference, :xor) on the subject and
      # clipping polygon sets.
      def self.run(subject, clipping, operation)
        clipper = Clipper::Clipper.new
        
        subject.polygons.each do |polygon|
          clipper.add_subject_polygon(polygon.each_vertex.map do |vertex| [vertex.x, vertex.y] end.reverse)
        end
        
        clipping.polygons.each do |polygon|
          clipper.add_clip_polygon(polygon.each_vertex.map do |vertex| [vertex.x, vertex.y] end.reverse)
        end
        
        result = Geom2D::PolygonSet.new
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
          polygon = Geom2D::Polygon.new	
          result << polygon
          points.map do |point|
            Geom2D::Point.new(point.first, point.last)
          end.each do |point|
            next if polygon.nr_of_vertices > 0 && point.distance(polygon[-1]) < 1e-3
            polygon << point
          end
          polygon.pop if polygon[0].distance(polygon[-1]) < 1e-3
        end
        
        return result
      end

    end

  end
end