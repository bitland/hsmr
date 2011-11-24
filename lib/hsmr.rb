require 'openssl'

module HSMR
  VERSION = '0.0.1'
  
  # Key Lengths
  SINGLE=64
  DOUBLE=128
  TRIPLE=192

  ## Mixin functionality
  
  def kcv()
    des = OpenSSL::Cipher::Cipher.new("des-cbc") if @key.length == 8
    des = OpenSSL::Cipher::Cipher.new("des-ede-cbc") if @key.length == 16
    des.encrypt
    des.key=@key
    des.update("\x00"*8).unpack('H*').first[0...6].upcase
  end

  def generate(length)
    (0...(length/4)).collect { rand(16).to_s(16).upcase }.join
  end


  def to_s
    @key.unpack('H4'*(@key.length/2)).join(" ").upcase
  end

  def odd_parity?
    # http://csrc.nist.gov/publications/nistpubs/800-67/SP800-67.pdf
    #
    # The eight error detecting bits are set to make the parity of each 8-bit 
    # byte of the key odd. That is, there is an odd number of "1"s in each 8-bit byte.

    #3.to_s(2).count('1')
    #@key.unpack("H2").first.to_i(16).to_s(2)

    working=@key.unpack('H2'*(@key.length))
    working.each do |o| 
      freq = o.to_i(16).to_s(2).count('1').to_i
      if( freq%2 == 0)
        #puts "#{o} is #{o.to_i(16).to_s(2).count('1').to_i } - even" 
        return false
      else
        return true
        #puts "#{o} is #{o.to_i(16).to_s(2).count('1').to_i } - odd" 
      end
    end      
  end

  def set_odd_parity
    return true if self.odd_parity? == true
        
    working=@key.unpack('H2'*(@key.length))
    working.each_with_index do |o,i|
      freq = o.to_i(16).to_s(2).count('1').to_i
      if( freq%2 == 0)
        c1 = o[0].chr
        c2 = case o[1].chr
          when "0" then "1"
          when "1" then "0"
          when "2" then "3"
          when "3" then "2"
          when "4" then "5"
          when "5" then "4"
          when "6" then "7"
          when "7" then "6"
          when "8" then "9"
          when "9" then "8"
          when "a" then "b"
          when "b" then "a"
          when "c" then "d"
          when "d" then "c"
          when "e" then "f"
          when "f" then "e"
        end
        working[i]="#{c1}#{c2}"
      end
    end
    @key = working.join.unpack('a2'*(working.length)).map{|x| x.hex}.pack('c'*(working.length))
  end

  ## Module Methods

  def self.encrypt_pin(key, pin)
    @pin = pin.unpack('a2'*(pin.length/2)).map{|x| x.hex}.pack('c'*(pin.length/2))
    des = OpenSSL::Cipher::Cipher.new("des-ede")
    des.encrypt
    des.key=key.key
    return des.update(@pin).unpack('H*').first.upcase
  end
  
  def self.decrypt_pin(key, pinblock)
    @pinblock = pinblock.unpack('a2'*(pinblock.length/2)).map{|x| x.hex}.pack('c'*(pinblock.length/2))
    des = OpenSSL::Cipher::Cipher.new("des-ede")
    des.decrypt
    des.padding=0
    des.key=key.key
    result = des.update(@pinblock)
    result << des.final
    result.unpack('H*').first.upcase
  end
  
  def self.ibm3624(key, account, plength=4, dtable="0123456789012345" )
    
    validation_data = account.unpack('a2'*(account.length/2)).map{|x| x.hex}.pack('c'*(account.length/2))

    #des = OpenSSL::Cipher::Cipher.new("des-ede-cbc")
    des = OpenSSL::Cipher::Cipher.new("des-cbc")
    des.encrypt
    des.key=key.key
    return HSMR::decimalise(des.update(validation_data).unpack('H*').first, :ibm, dtable)[0...plength]
    
  end
  
  def self.decimalise(value, method=:visa, dtable="0123456789012345" )

    result = []
    if method == :ibm  
      ##
      # The IBM method
      ##
      value.each_char do |c| 
        result << dtable[c.to_i(16),1].to_i
      end
      
    elsif method == :visa
      
      value.each_char do |c|
        result << c.to_i if numeric?(c)
      end
    
      value.upcase.each_char do |c|
        result << dtable[c.to_i(16),1].to_i unless numeric?(c)
      end
      
    end
    
    return result
  end
    
  def self.pvv(key, account, pvki, pin)
    tsp = account.to_s[4,11] + pvki.to_s + pin.to_s
    @tsp = tsp.unpack('a2'*(tsp.length/2)).map{|x| x.hex}.pack('c'*(tsp.length/2))
    des = OpenSSL::Cipher::Cipher.new("des-ede")
    des.encrypt
    des.key=key.key
    result = des.update(@tsp).unpack('H*').first.upcase
    decimalise(result, :visa)[0..3].join
  end

  def self.cvv(key_left, key_right, account, exp, service_code)
    
  end
  
  def self.xor(component1, *rest)
    return if rest.length == 0
    
    component1 = Component.new(component1) unless component1.is_a? Component
    raise TypeError, "Component argument expected" unless component1.is_a? Component
    
    #@components=[]
    #rest.each {|c| components << ((c.is_a? HSMR::Component) ? c : HSMR::Component.new(c) ) }
    #components.each {|c| raise TypeError, "Component argument expected" unless c.is_a? Component }
    #resultant = component1.xor(components.pop)
    #components.each {|c| resultant.xor!(c) }

    rest.collect! {|c| ( (c.is_a? HSMR::Component) ? c : HSMR::Component.new(c) ) }
    rest.each {|c| raise TypeError, "Component argument expected" unless c.is_a? HSMR::Component }
    resultant = component1.xor(rest.pop)
    rest.each {|c| resultant.xor!(c) }

    return(resultant)
  end
  
  def self.numeric?(object)
    ## Method to determine if an object is a numeric type.
    true if Float(object) rescue false
  end
end


class String
  def xor(other)
    if other.empty?
      self
    else
      a1        = self.unpack("c*")
      a2        = other.unpack("c*")
      a2 *= 2   while a2.length < a1.length
      a1.zip(a2).collect{|c1,c2| c1^c2}.pack("c*")
    end
  end
end
