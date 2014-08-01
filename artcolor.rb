require 'colorscore'
require 'chunky_png'
require 'listen'
require 'fileutils'
include Colorscore

#keep track so you dont do redundant things
$track = ""
$artist = ""
$album = ""
$primary
$secondary
$outline

Thread.abort_on_exception=true

def get_primary_and_secondary(filename)

  #break down what % of pixels are what color
  histogram = Histogram.new(filename)

  #bucket these colors by similarity
  buckets = {}

  #go through and find colors most similar to the most common color, and then loop for colors remaining until we're out of colors
  next_loop = histogram.scores

  while !next_loop.empty?

    scores = next_loop
    current = next_loop.first
    if current.nil? || current[1].nil? || scores[0].nil? || scores[0][1].nil? #i dunno keep checking things until i figure out how to not make it error
      sleep 0.1 #wait and retry
      return get_primary_and_secondary(filename)
    end
    next_loop = []
    buckets[current], next_loop = scores.partition{|s| Metrics.similarity(current[1], s[1]) > 0.75}

  end

  #find which bucket contains the highest # of pixels
  wb = []
  buckets.each do |k,v|
    weight = v.inject(0.0) { |sum, color| sum + color[0] } #sum weights in the bucket
    wb << [k[1], weight]
  end

  wb.sort_by! { |x| x[1]  }.reverse!

  #error => retry in a bit?
  if wb[0].nil?
    sleep 0.1
    return get_primary_and_secondary(filename)
  end
  primary = wb[0][0]

  outline = [Color::RGB.by_hex('000000'), Color::RGB.by_hex('ffffff')].map{|c| [c, Metrics.distance(c, primary)]}.max_by{|x| x[1]}[0]

  if wb.length > 1
    secondary = wb[1][0]
  else #if theres only one color in the image then select whichever would contrast more, black or white
    secondary = outline
  end

  return primary, secondary, outline

end


def create_text_images(title, artist, color, outline)

  %x{convert -background none -fill ##{color.hex} -stroke ##{outline.hex} -strokewidth 0.5 -font Arial-Bold -pointsize 18 -size 180x70 -gravity center caption:"#{title}" assets/title.png}
  %x{convert -background none -fill ##{color.hex} -stroke ##{outline.hex} -strokewidth 0.5 -font Arial-Bold -pointsize 24 -size 180x50 -gravity center caption:"#{artist}" assets/artist.png}

end

def create_background_image(color)

  %x{convert -size 640x360 xc:##{color.hex} assets/background.png}

end

def copy_album_art

  FileUtils.cp('Snip_Artwork.jpg', 'assets/')

end

#do it at startup, also get rid of this repeated code eventually(?)
$track = File.read('Snip_Track.txt')
$artist = File.read('Snip_Artist.txt')
$album = File.read('Snip_Album.txt')
$primary, $secondary, $outline = get_primary_and_secondary('Snip_Artwork.jpg')
create_background_image($primary)
create_text_images($track, $artist, $secondary, $outline)
copy_album_art 

listener = Listen.to('.',) do |modified, added, removed|
  puts "modified absolute path: #{modified[0].split("/")[-1]}"
  if modified[0].split("/")[-1].downcase.include? "snip"
    Thread.new do
      track = File.read('Snip_Track.txt')
      artist = File.read('Snip_Artist.txt')
      album = File.read('Snip_Album.txt')
      sleep 0.250
      if ($primary.nil? && $secondary.nil? && $outline.nil?) || album != $album #if we dont already have colors set or if the album changes. don't know how they could be nil, but check.
        puts "album changed - was #{$album}, now #{album}"
        $primary, $secondary, $outline = get_primary_and_secondary('Snip_Artwork.jpg') #get the color, set the globals
        create_background_image($primary) #create a new background
        copy_album_art #image creation is delayed, so delay the album art showing up as well
        create_text_images(track, artist, $secondary, $outline)
      elsif track != $track || artist != $artist #just update the text images if album doesnt change
        puts "track changed - was #{$track} by #{$artist}, now #{track} by #{artist}"
        create_text_images(track, artist, $secondary, $outline)
      end

      $track = track
      $album = album
      $artist = artist

    end
  end
  STDOUT.flush
end
listener.start # not blocking
sleep
