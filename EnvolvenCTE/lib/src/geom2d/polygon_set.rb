# -*- frozen_string_literal: true -*-
#
#--
# geom2d - 2D Geometric Objects and Algorithms
# Copyright (C) 2018 Thomas Leitner <t_leitner@gmx.at>
#
# This software may be modified and distributed under the terms
# of the MIT license.  See the LICENSE file for details.
#++

module Geom2D

  # Represents a set of polygons.
  class PolygonSet

    # The array of polygons.
    attr_reader :polygons

    # Creates a new PolygonSet with the given polygons.
    def initialize(polygons = [])
      @polygons = polygons
    end

    # Adds a polygon to this set.
    def add(polygon)
      @polygons << polygon
      self
    end
    alias << add

    # Creates a new polygon set by combining the polygons from this set and the other one.
    def join(other)
      PolygonSet.new(@polygons + other.polygons)
    end
    alias + join

    # Calls the given block once for each segment of each polygon in the set.
    #
    # If no block is given, an Enumerator is returned.
    def each_segment(&block)
      return to_enum(__method__) unless block_given?
      @polygons.each {|polygon| polygon.each_segment(&block) }
    end

    # Returns the number of polygons in this set.
    def nr_of_contours
      @polygons.size
    end

    # Returns the BoundingBox of all polygons in the set, or +nil+ if it contains no polygon.
    def bbox
      return BoundingBox.new if @polygons.empty?
      result = @polygons.first.bbox
      @polygons[1..-1].each {|v| result.add!(v.bbox) }
      result
    end

    def inspect #:nodoc:
      "PolygonSet#{@polygons}"
    end
    alias to_s inspect
    
    
    def front(segment)
      front = PolygonSet.new

      length = segment.length
      return front if Utils.float_compare(length, 0) < 1
      
      @polygons.each do |polygon|
        px, py = segment.start_point.x, segment.start_point.y
        v = segment.end_point - segment.start_point
        dx, dy = v.x.to_f / length, v.y.to_f / length
        d = px*dy - py*dx
        
        distances = []
        each_segment do |polygon_segment|
          distances << polygon_segment.start_point.x*dy - polygon_segment.start_point.y*dx - d
        end
        
        polygon_set = PolygonSet.new([polygon])
        if Utils.float_compare(distances.min, 0) > -1 then
          front = front.join(polygon_set)
          next
        end
        distance = distances.max
        next if Utils.float_compare(distance, 0) < 1

        points = case
        when Utils.float_equal(dx, 0) then [Point.new(px, bbox.min_y), Point.new(px, bbox.max_y)]
        when Utils.float_equal(dy, 0) then [Point.new(bbox.min_x, py), Point.new(bbox.max_x, py)]
        else
          [(bbox.min_x - px) / dx, (bbox.max_x - px) / dx, (bbox.min_y - py) / dy, (bbox.max_y - py) / dy].sort.values_at(0,-1).map do |t|
            Point.new(px + t*dx, py + t*dy)
          end
        end
        bbox_segment = Segment.new(points.first, points.last)
        bbox_segment.reverse! if Utils.float_compare(dx * (bbox_segment.end_point.x - bbox_segment.start_point.x), 0) < 0
        
        clipping = PolygonSet.new([Polygon.new([
          [bbox_segment.start_point.x, bbox_segment.start_point.y],
          [bbox_segment.end_point.x, bbox_segment.end_point.y],
          [bbox_segment.end_point.x + dy*distance, bbox_segment.end_point.y - dx*distance],
          [bbox_segment.start_point.x + dy*distance, bbox_segment.start_point.y - dx*distance]
        ])])

        front = front.join(Algorithms::PolygonOperation.run(polygon_set, clipping, :intersection))
      end
      
      return front
    end
    
    def area
      @polygons.inject(0.0) do |sum, polygon| sum + polygon.area end.abs
    end
    
  end
end