# pure_lua_GIF

GIF decoder in pure Lua

### Installation

Just copy "gif.lua" to Lua modules' folder.

### Decoding

```lua
local filename = "SOME_PICTURE.gif"

-- Create "GIF object" for specified file (the file will be opened as read-only)
local gif = require('gif')(filename)

-- Extract some information about this GIF
local w, h = gif.get_width_height()
print('Picture dimensions: '        .. w..' x '..h)
print('Number of animation frames: '.. gif.get_file_parameters().number_of_images)
print('Comment inside this GIF: '   ..(gif.get_file_parameters().comment or 'NO_COMMENT'))

-- Get the color of pixel with coordinates (2,0)
local matrix = gif.read_matrix()   -- first animation frame of this GIF as 2D-matrix of colors
local row = 1    -- top row of the picture
local col = 3    -- third pixel from the left
local color = matrix[row][col]
if color == -1 then
   print("This pixel is transparent")
else
   print(("The color of this pixel in hexadecimal RRGGBB format is %06X"):format(color))
end

-- Close "GIF object" (file will be closed now)
gif.close()
```
