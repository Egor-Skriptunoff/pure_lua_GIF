-- Example of non-animated gif:
local filename = "mini-graphics-ducks-425811.gif"
-- This .GIF was downloaded from:
-- http://www.picgifs.com/mini-graphics/mini-graphics/ducks/mini-graphics-ducks-425811.gif

--[[
-- Example of animated gif:
local filename = "mini-graphics-cats-864491.gif"
-- This .GIF was downloaded from:
-- http://www.picgifs.com/mini-graphics/mini-graphics/cats/mini-graphics-cats-864491.gif
--]]

local gif = require'gif'(filename)
local w, h = gif.get_width_height()
print('Picture dimensions: '..w..' x '..h)
print('Total Frames: '..gif.get_file_parameters().number_of_images)
print('Comment: '..(gif.get_file_parameters().comment or 'NO_COMMENT'))
print('Looped: '..(gif.get_file_parameters().looped and 'YES' or 'NO'))
repeat
   local image_no = gif.get_image_parameters().image_no
   print("Frame #"..image_no)
   local m = gif.read_matrix()
   -- Print the matrix for this frame
   for row = 1, #m do
      local r = {}
      for col = 1, #m[1] do
         local color = m[row][col]
         if color == -1 then  -- Transparent color
            color = "------"
         else                 -- Non-transparent color in 0xRRGGBB format
            color = ("%06X"):format(color)
         end
         table.insert(r, color)
      end
      print(table.concat(r, "  "))
   end
until not gif.next_image()  -- try to switch to next animation frame
gif.close()
