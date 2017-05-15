--------------------------------------------------------------------------------------------------------------------------
-- Decoder of GIF-files
--------------------------------------------------------------------------------------------------------------------------
-- This module extracts images from GIF-files.
-- Written in pure Lua.
-- Compatible with Lua 5.1, 5.2, 5.3, LuaJIT.

-- Version 1  (2017-05-15)

-- require('gif')(filename) opens .gif-file for read-only and returns "GifObject" having the following functions:
--    read_matrix(x, y, width, height)
--       returns current image (one animated frame) as 2D-matrix of colors (as nested Lua tables)
--       by default whole non-clipped picture is returned
--       pixels are numbers: (-1) for transparent color, 0..0xFFFFFF for 0xRRGGBB color
--    get_width_height()
--       returns two integers (width and height are the properties of the whole file)
--    get_file_parameters()
--       returns table with the following fields (these are the properties of the whole file)
--          comment           -- text coment inside gif-file
--          looped            -- boolean
--          number_of_images  -- == 1 for non-animated gifs, > 1 for animated gifs
--    get_image_parameters()
--       returns table with fields image_no and delay_in_ms (these are properties of the current animation frame)
--    next_image(looping_mode)
--       switches to next frame, returns false if failed to switch
--       looping_mode = 'never' (default) - never wrap from the last frame to the first
--                      'always'          - always wrap from the last frame to the first
--                      'play'            - depends on whether or not .gif-file is marked as looped gif
--    close()
--------------------------------------------------------------------------------------------------------------------------

local unpack, floor = table.unpack or unpack, math.floor
local is_windows = (os.getenv'oS' or ""):match'^Windows'

--------------------------------------------------------------------------------------------------------------------------
local function open_file_buffer(filename)    -- open file for read-only, returns InputBufferObject

   local input_buffer_object = {}
   local intel_byte_order = true
   local file = assert(io.open(filename, is_windows and 'rb' or 'r'))
   local file_size = assert(file:seek'end')
   assert(file:seek'set')

   input_buffer_object.file_size = file_size

   local user_offset = 0

   function input_buffer_object.jump(offset)
      user_offset = offset
      return input_buffer_object
   end

   function input_buffer_object.skip(delta_offset)
      user_offset = user_offset + delta_offset
      return input_buffer_object
   end

   function input_buffer_object.get_offset()
      return user_offset
   end

   local file_blocks = {}   -- [block_index] = {index=block_index, data=string, more_fresh=obj_ptr, more_old=obj_ptr}
   local cached_blocks = 0  -- number if block indices in use in the array file_blocks
   local chain_terminator = {}
   chain_terminator.more_fresh = chain_terminator
   chain_terminator.more_old = chain_terminator
   local function remove_from_chain(object_to_remove)
      local more_fresh_object = object_to_remove.more_fresh
      local more_old_object = object_to_remove.more_old
      more_old_object.more_fresh = more_fresh_object
      more_fresh_object.more_old = more_old_object
   end
   local function insert_into_chain(object_to_insert)
      local old_freshest_object = chain_terminator.more_old
      object_to_insert.more_fresh = chain_terminator
      object_to_insert.more_old = old_freshest_object
      old_freshest_object.more_fresh = object_to_insert
      chain_terminator.more_old = object_to_insert
   end
   local function get_file_block(block_index)
      -- blocks are aligned to 32K boundary, indexed from 0
      local object = file_blocks[block_index]
      if not object then
         if cached_blocks < 3 then
            cached_blocks = cached_blocks + 1
         else
            local object_to_remove = chain_terminator.more_fresh
            remove_from_chain(object_to_remove)
            file_blocks[object_to_remove.index] = nil
         end
         local block_offset = block_index * 32*1024
         local block_length = math.min(32*1024, file_size - block_offset)
         assert(file:seek('set', block_offset))
         local content = file:read(block_length)
         assert(#content == block_length)
         object = {index = block_index, data = content}
         insert_into_chain(object)
         file_blocks[block_index] = object
      elseif object.more_fresh ~= chain_terminator then
         remove_from_chain(object)
         insert_into_chain(object)
      end
      return object.data
   end

   function input_buffer_object.close()
      file_blocks = nil
      chain_terminator = nil
      file:close()
   end

   function input_buffer_object.read_string(length)
      assert(length >= 0, 'negative string length')
      assert(user_offset >= 0 and user_offset + length <= file_size, 'attempt to read beyond the file boundary')
      local str, arr = ''
      while length > 0 do
         local offset_inside_block = user_offset % (32*1024)
         local part_size = math.min(32*1024 - offset_inside_block, length)
         local part = get_file_block(floor(user_offset / (32*1024))):sub(1 + offset_inside_block, part_size + offset_inside_block)
         user_offset = user_offset + part_size
         length = length - part_size
         if arr then
            table.insert(arr, part)
         elseif str ~= '' then
            str = str..part
         elseif length > 32*1024 then
            arr = {part}
         else
            str = part
         end
      end
      return arr and table.concat(arr) or str
   end

   function input_buffer_object.read_byte()
      return input_buffer_object.read_bytes(1)
   end

   function input_buffer_object.read_word()
      return input_buffer_object.read_words(1)
   end

   function input_buffer_object.read_bytes(quantity)
      return input_buffer_object.read_string(quantity):byte(1, -1)
   end

   function input_buffer_object.read_words(quantity)
      return unpack(input_buffer_object.read_array_of_words(quantity))
   end

   local function read_array_of_numbers_of_k_bytes_each(elems_in_array, k)
      if k == 1 and elems_in_array <= 100 then
         return {input_buffer_object.read_string(elems_in_array):byte(1, -1)}
      else
         local array_of_numbers = {}
         local max_numbers_in_string = floor(100 / k)
         for number_index = 1, elems_in_array, max_numbers_in_string do
            local numbers_in_this_part = math.min(elems_in_array - number_index + 1, max_numbers_in_string)
            local part = input_buffer_object.read_string(numbers_in_this_part * k)
            if k == 1 then
               for delta_index = 1, numbers_in_this_part do
                  array_of_numbers[number_index + delta_index - 1] = part:byte(delta_index)
               end
            else
               for delta_index = 0, numbers_in_this_part - 1 do
                  local number = 0
                  for byte_index = 1, k do
                     local pos = delta_index * k + (intel_byte_order and k + 1 - byte_index or byte_index)
                     number = number * 256 + part:byte(pos)
                  end
                  array_of_numbers[number_index + delta_index] = number
               end
            end
         end
         return array_of_numbers
      end
   end

   function input_buffer_object.read_array_of_words(elems_in_array)
      return read_array_of_numbers_of_k_bytes_each(elems_in_array, 2)
   end

   return input_buffer_object

end

--------------------------------------------------------------------------------------------------------------------------

local function open_gif(filename)
   -- open picture for read-only, returns InputGifObject
   local gif = {}
   local input = open_file_buffer(filename)
   assert(({GIF87a=0,GIF89a=0})[input.read_string(6)], 'wrong file format')
   local gif_width, gif_height = input.read_words(2)
   assert(gif_width ~= 0 and gif_height ~= 0, 'wrong file format')

   function gif.get_width_height()
      return gif_width, gif_height
   end

   local global_flags = input.read_byte()
   input.skip(2)
   local global_palette           -- 0-based global palette array (or nil)
   if global_flags >= 0x80 then
      global_palette = {}
      for color_index = 0, 2^(global_flags % 8 + 1) - 1 do
         local R, G, B = input.read_bytes(3)
         global_palette[color_index] = R * 2^16 + G * 2^8 + B
      end
   end
   local first_frame_offset = input.get_offset()

   local file_parameters                   -- initially nil, filled after finishing first pass
   local fp_comment, fp_looped_animation   -- for storing parameters before first pass completed
   local fp_number_of_frames = 0
   local fp_last_processed_offset = 0

   local function fp_first_pass()
      if not file_parameters then
         local current_offset = input.get_offset()
         if current_offset > fp_last_processed_offset then
            fp_last_processed_offset = current_offset
            return true
         end
      end
   end

   local function skip_to_end_of_block()
      repeat
         local size = input.read_byte()
         input.skip(size)
      until size == 0
   end

   local function skip_2C()
      input.skip(8)
      local local_flags = input.read_byte()
      if local_flags >= 0x80 then
         input.skip(3 * 2^(local_flags % 8 + 1))
      end
      input.skip(1)
      skip_to_end_of_block()
   end

   local function process_blocks(callback_2C, callback_21_F9)
      -- processing blocks of GIF-file
      local exit_reason
      repeat
         local starter = input.read_byte()
         if starter == 0x3B then        -- EOF marker
            if fp_first_pass() then
               file_parameters = {comment = fp_comment, looped = fp_looped_animation, number_of_images = fp_number_of_frames}
            end
            exit_reason = 'EOF'
         elseif starter == 0x2C then    -- image marker
            if fp_first_pass() then
               fp_number_of_frames = fp_number_of_frames + 1
            end
            exit_reason = (callback_2C or skip_2C)()
         elseif starter == 0x21 then
            local fn_no = input.read_byte()
            if fn_no == 0xF9 then
               (callback_21_F9 or skip_to_end_of_block)()
            elseif fn_no == 0xFE and not fp_comment then
               fp_comment = {}
               repeat
                  local size = input.read_byte()
                  table.insert(fp_comment, input.read_string(size))
               until size == 0
               fp_comment = table.concat(fp_comment)
            elseif fn_no == 0xFF and input.read_string(input.read_byte()) == 'NETSCAPE2.0' then
               fp_looped_animation = true
               skip_to_end_of_block()
            else
               skip_to_end_of_block()
            end
         else
            error'wrong file format'
         end
      until exit_reason
      return exit_reason
   end

   function gif.get_file_parameters()
      if not file_parameters then
         local saved_offset = input.get_offset()
         process_blocks()
         input.jump(saved_offset)
      end
      return file_parameters
   end

   local loaded_frame_no = 0          --\ frame parameters (frame_no = 1, 2, 3,...)
   local loaded_frame_delay           --/
   local loaded_frame_action_on_background
   local loaded_frame_transparent_color_index
   local loaded_frame_matrix                  -- picture of the frame        \ may be two pointers to the same matrix
   local background_matrix_after_loaded_frame -- background for next picture /
   local background_rectangle_to_erase        -- nil or {left, top, width, height}

   function gif.read_matrix(x, y, width, height)
      -- by default whole picture rectangle
      x, y = x or 0, y or 0
      width, height = width or gif_width - x, height or gif_height - y
      assert(x >= 0 and y >= 0 and width >= 1 and height >= 1 and x + width <= gif_width and y + height <= gif_height,
            'attempt to read pixels out of the picture boundary')
      local matrix = {}
      for row_no = 1, height do
         matrix[row_no] = {unpack(loaded_frame_matrix[row_no + y], x + 1, x + width)}
      end
      return matrix
   end

   function gif.close()
      loaded_frame_matrix = nil
      background_matrix_after_loaded_frame = nil
      input.close()
   end

   function gif.get_image_parameters()
      return {image_no = loaded_frame_no, delay_in_ms = loaded_frame_delay}
   end

   local function callback_2C()
      if background_rectangle_to_erase then
         local left, top, width, height = unpack(background_rectangle_to_erase)
         background_rectangle_to_erase = nil
         for row = top + 1, top + height do
            local line = background_matrix_after_loaded_frame[row]
            for col = left + 1, left + width do
               line[col] = -1
            end
         end
      end
      loaded_frame_action_on_background = loaded_frame_action_on_background or 'combine'
      local left, top, width, height = input.read_words(4)
      assert(width ~= 0 and height ~= 0 and left + width <= gif_width and top + height <= gif_height, 'wrong file format')
      local local_flags = input.read_byte()
      local interlaced = local_flags % 0x80 >= 0x40
      local palette = global_palette          -- 0-based palette array
      if local_flags >= 0x80 then
         palette = {}
         for color_index = 0, 2^(local_flags % 8 + 1) - 1 do
            local R, G, B = input.read_bytes(3)
            palette[color_index] = R * 2^16 + G * 2^8 + B
         end
      end
      assert(palette, 'wrong file format')
      local bits_in_color = input.read_byte()  -- number of colors in LZW voc

      local bytes_in_current_part_of_stream = 0
      local function read_byte_from_stream()   -- returns next byte or false
         if bytes_in_current_part_of_stream > 0 then
            bytes_in_current_part_of_stream = bytes_in_current_part_of_stream - 1
            return input.read_byte()
         else
            bytes_in_current_part_of_stream = input.read_byte() - 1
            return bytes_in_current_part_of_stream >= 0 and input.read_byte()
         end
      end

      local CLEAR_VOC = 2^bits_in_color
      local END_OF_STREAM = CLEAR_VOC + 1

      local LZW_voc         -- [code] = {prefix_code, color_index}
      local bits_in_code = bits_in_color + 1
      local next_power_of_two = 2^bits_in_code
      local first_undefined_code, need_completion

      local stream_bit_buffer = 0
      local bits_in_buffer = 0
      local function read_code_from_stream()
         while bits_in_buffer < bits_in_code do
            stream_bit_buffer = stream_bit_buffer + assert(read_byte_from_stream(), 'wrong file format') * 2^bits_in_buffer
            bits_in_buffer = bits_in_buffer + 8
         end
         local code = stream_bit_buffer % next_power_of_two
         stream_bit_buffer = (stream_bit_buffer - code) / next_power_of_two
         bits_in_buffer = bits_in_buffer - bits_in_code
         return code
      end

      assert(read_code_from_stream() == CLEAR_VOC, 'wrong file format')

      local function clear_LZW_voc()
         LZW_voc = {}
         bits_in_code = bits_in_color + 1
         next_power_of_two = 2^bits_in_code
         first_undefined_code = CLEAR_VOC + 2
         need_completion = nil
      end

      clear_LZW_voc()

      -- Copy matrix background_matrix_after_loaded_frame to loaded_frame_matrix

      if loaded_frame_action_on_background == 'combine' or loaded_frame_action_on_background == 'erase' then
         loaded_frame_matrix = background_matrix_after_loaded_frame
      else  -- 'undo'
         loaded_frame_matrix = {}
         for row = 1, gif_height do
            loaded_frame_matrix[row] = {unpack(background_matrix_after_loaded_frame[row])}
         end
      end

      -- Decode and apply image delta (window: left, top, width, height) on the matrix loaded_frame_matrix

      local pixels_remained = width * height
      local x_inside_window, y_inside_window  -- coordinates inside window
      local function pixel_from_stream(color_index)
         pixels_remained = pixels_remained - 1
         assert(pixels_remained >= 0, 'wrong file format')
         if x_inside_window then
            x_inside_window = x_inside_window + 1
            if x_inside_window == width then
               x_inside_window = 0
               if interlaced then
                  repeat
                     if y_inside_window % 8 == 0 then
                        y_inside_window = y_inside_window < height and y_inside_window + 8 or 4
                     elseif y_inside_window % 4 == 0 then
                        y_inside_window = y_inside_window < height and y_inside_window + 8 or 2
                     elseif y_inside_window % 2 == 0 then
                        y_inside_window = y_inside_window < height and y_inside_window + 4 or 1
                     else
                        y_inside_window = y_inside_window + 2
                     end
                  until y_inside_window < height
               else
                  y_inside_window = y_inside_window + 1
               end
            end
         else
            x_inside_window, y_inside_window = 0, 0
         end
         if color_index ~= loaded_frame_transparent_color_index then
            loaded_frame_matrix[top + y_inside_window + 1][left + x_inside_window + 1]
               = assert(palette[color_index], 'wrong file format')
         end
      end

      repeat
         -- LZW_voc: [code] = {prefix_code, color_index}
         -- all the codes (CLEAR_VOC+2)...(first_undefined_code-2) are defined completely
         -- the code (first_undefined_code-1) has defined only its first component
         local code = read_code_from_stream()
         if code == CLEAR_VOC then
            clear_LZW_voc()
         elseif code ~= END_OF_STREAM then
            assert(code < first_undefined_code, 'wrong file format')
            local stack_of_pixels = {}
            local pos = 1
            local first_pixel = code
            while first_pixel >= CLEAR_VOC do
               first_pixel, stack_of_pixels[pos] = unpack(LZW_voc[first_pixel])
               pos = pos + 1
            end
            stack_of_pixels[pos] = first_pixel
            if need_completion then
               need_completion = nil
               LZW_voc[first_undefined_code - 1][2] = first_pixel
               if code == first_undefined_code - 1 then
                  stack_of_pixels[1] = first_pixel
               end
            end
            -- send pixels for phrase "code" to result matrix
            for pos = pos, 1, -1 do
               pixel_from_stream(stack_of_pixels[pos])
            end
            if first_undefined_code < 0x1000 then
               -- create new code
               LZW_voc[first_undefined_code] = {code}
               need_completion = true
               if first_undefined_code == next_power_of_two then
                  bits_in_code = bits_in_code + 1
                  next_power_of_two = 2^bits_in_code
               end
               first_undefined_code = first_undefined_code + 1
            end
         end
      until code == END_OF_STREAM

      assert(pixels_remained == 0 and stream_bit_buffer == 0, 'wrong file format')
      local extra_byte = read_byte_from_stream()
      assert(not extra_byte or extra_byte == 0 and not read_byte_from_stream(), 'wrong file format')

      -- Modify the matrix background_matrix_after_loaded_frame
      if loaded_frame_action_on_background == 'combine' then
         background_matrix_after_loaded_frame = loaded_frame_matrix
      elseif loaded_frame_action_on_background == 'erase' then
         background_matrix_after_loaded_frame = loaded_frame_matrix
         background_rectangle_to_erase = {left, top, width, height}
      end
      loaded_frame_no = loaded_frame_no + 1
      return 'OK'
   end

   local function callback_21_F9()
      local len, flags = input.read_bytes(2)
      local delay = input.read_word()
      local transparent, terminator = input.read_bytes(2)
      assert(len == 4 and terminator == 0, 'wrong file format')
      loaded_frame_delay = delay * 10
      if flags % 2 == 1 then
         loaded_frame_transparent_color_index = transparent
      end
      local method = floor(flags / 4) % 8
      if method == 2 then
         loaded_frame_action_on_background = 'erase'
      elseif method == 3 then
         loaded_frame_action_on_background = 'undo'
      end
   end

   local function load_next_frame()
      -- returns true if next frame was loaded (of false if there is no next frame)
      if loaded_frame_no == 0 then
         background_matrix_after_loaded_frame = {}
         for y = 1, gif_height do
            background_matrix_after_loaded_frame[y] = {}
         end
         background_rectangle_to_erase = {0, 0, gif_width, gif_height}
         input.jump(first_frame_offset)
      end
      loaded_frame_delay = nil
      loaded_frame_action_on_background = nil
      loaded_frame_transparent_color_index = nil
      return process_blocks(callback_2C, callback_21_F9) ~= 'EOF'
   end

   assert(load_next_frame(), 'wrong file format')

   local looping_modes = {never=0, always=1, play=2}
   function gif.next_image(looping_mode)
      -- switches to next image, returns true/false, false means failed to switch
      -- looping_mode = 'never'/'always'/'play'
      local looping_mode_no = looping_modes[looping_mode or 'never']
      assert(looping_mode_no, 'wrong looping mode')
      if load_next_frame() then
         return true
      else
         if ({0, fp_looped_animation})[looping_mode_no] then  -- looping now
            loaded_frame_no = 0
            return load_next_frame()
         else
            return false
         end
      end
   end

   return gif
end

--------------------------------------------------------------------------------------------------------------------------

return open_gif
