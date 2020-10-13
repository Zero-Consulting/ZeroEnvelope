
class Utilities

  def self.fix_name(name)
    return name.gsub("&lt;", "<").gsub("&gt;", ">")
  end

  @convert_hash = {}
  
  def self.convert(original, original_units, final_units)
    original_hash = @convert_hash[original_units] || {}
    original_final = original_hash[final_units]
    return original * original_final unless original_final.nil?
    
    original_final = OpenStudio.convert(1.0, original_units, final_units).get
    original_hash[final_units] = original_final
    @convert_hash[original_units] = original_hash
    
    final_hash = @convert_hash[final_units] || {}
    final_hash[original_units] = 1.0 / original_final
    @convert_hash[final_units] = final_hash
    
    return original * original_final
  end

  def self.capitalize_all(string, char = "")
    return string.split("_").each.map do |x| 
      aux = x[0]
      if aux.downcase.eql?(aux) then
        x.capitalize
      else
        x
      end
    end.join(char)
  end
  
  def self.capitalize_all_but_first(string)
    string = self.capitalize_all(string) 
    string[0] = string[0].downcase
    
    return string
  end
  
  def self.merge(neighbours)
    objects = []

    neighbours.each do |object, object_neighbours|
      merge = true
      objects.each do |object_objects|
        next unless object_objects.include?(object)
        merge = false
        break
      end
      next unless merge
      
      object_objects = [object]+object_neighbours
      while true
        new_object_objects = []
        object_objects.each do |object_object|
          (neighbours[object_object] || []).each do |object_object_neighbour|
            next if object_objects.include?(object_object_neighbour)
            next if new_object_objects.include?(object_object_neighbour)
            new_object_objects << object_object_neighbour
          end
        end
        
        break if new_object_objects.empty?
        object_objects += new_object_objects
      end
      
      objects << object_objects
    end
    
    return objects
  end
  
end