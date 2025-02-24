module markdown;
import js::console;
import std::io;
import std::io::file;

fn void main() @if(!env::WASM_NOLIBC){
    String testFile = (String) file::load_new("./test.md", allocator::heap())!!;
    // console::log("Loaded!");
    int outSize;
    char* output = js_md_to_html(testFile.ptr, testFile.len, &outSize);
    // console::log("%s", (String)output[0..outSize]);
    file::save("testOut.html", output[:outSize])!!;
    testFile.free();
    allocator::free(allocator::heap(), output);
}

fn char* js_md_to_html(char* buffer, usz buffer_sz, int* size) @wasm @extern("js_md_to_html") {
    ByteReader byteBuffer;
    byteBuffer.init(buffer[0..buffer_sz]);
    console::log("Input: %s", (String) byteBuffer.bytes);
    Html md = md_stream_to_html(&byteBuffer);
    *size = (int) md.size;
    return md.data;
} 

struct Html{
    char* data;
    usz size;
}

macro char! InStream.peek(&self){
    char! ret = self.read_byte();
    self.pushback_byte()!!;
    return ret;
}

macro usz InStream.count(&self, char c){
    usz count;
    do{
        if(self.read_byte()!! == c){
            count++;
        }else{
            self.pushback_byte()!!;
            break;
        }
    }while(self.available()!! > 0);
    return count;
}

macro bool InStream.empty_till_new_line(&self){
    do{
        char! c = self.read_byte();
        if(try c){
            switch(c){
                case ' ':
                case '\r':
                case '\t':
                    continue;
                case '\n':
                    return true;
                default:
                    self.pushback_byte()!!;
                    return false;
            }
        }
    }while(self.available()!!);
    return true;
}

macro void InStream.skip_till_characters(&self){
    do{
        char! c = self.read_byte();
        if(try c) switch(c){
            case ' ':
            case '\r':
            case '\t':
            case '\n':
                continue;
            default: 
                self.pushback_byte()!!;
                return;
        }
    }while(self.available()!!);
}

macro void InStream.append_till_character(&self, DString* buffer, char key){
    do{
        char! c = self.read_byte();
        if(try c) switch(c){
            case key:
                self.pushback_byte()!!;
                return;
            default: 
                buffer.append_char(c);
                continue;
        }
    }while(self.available()!!);
}

enum MDState{
    START_OF_LINE,
    HEADER,
    TEXT,
    BULLET_POINT,
}


<*
    @require &(stream.read_byte) != null
    @require &(stream.pushback_byte) != null
    @require &(stream.available) != null
*>
fn Html md_stream_to_html(InStream stream) @wasm @extern("md_stream_to_html"){
    //String font_weight; //= starCount >= 2 ? "bold" : "normal";
    //String font_style ; //= starCount == 1 || starCount == 3 ? "italic" : "normal";
    DString output;
    output.new_init();
    defer output.free();
    MDState state = MDState.START_OF_LINE;
    bool bold;
    bool italic;
    bool bullets;
    usz headerSize;
    while(true){
        char! current = stream.read_byte();
        // console::log("LOOP");
        if(catch e = current){
            output.append("</span>");
            break;
        }
        if(current == '/r' || current == 0) continue;
        switch(state){
            case MDState.START_OF_LINE: 
                if(current == '#'){
                    headerSize = stream.count('#') + 1;
                    // console::log("START_OF_LINE, Current: %c", current);
                    console::log("%d", headerSize);
                    if(stream.available()!! > 0 && stream.peek()!! == ' ' && headerSize <= 6){
                        state = MDState.HEADER;
                        DString temp;
                        temp.new_init();
                        temp.appendf("h%d", headerSize);
                        output.append_html(temp.str_view(),bold, italic);
                        temp.free();
                    }else{
                        state = MDState.TEXT;
                        int t = (int) headerSize;
                        for(; headerSize; headerSize--){
                            output.append_char('#');
                        }   
                    }
                }else if (current == '-' || current == '*'){
                    if(stream.peek()!! == ' '){
                        state = MDState.BULLET_POINT;
                        stream.read_byte()!!;
                        if(!bullets){
                            output.append_html("ul", bold, italic);
                        }
                        output.append_html("li", bold, italic);
                        bullets = true;
                    }else if(current == '*') {
                        if(bullets){
                            output.append("</ul>");
                            bullets = false;
                        }
                        state = MDState.TEXT;
                        usz stars = stream.count('*') + 1;
                        if(stars == 1 || stars == 3){
                            italic = !italic;
                        }
                        if(stars == 2){
                            bold = !bold;
                        }
                        output.append("</span>");
                        output.append_html("span", bold, italic);
                    }
                    else{
                        // if(bullets){
                        //     output.append("</ul>");
                        //     bullets = false;
                        // }
                        state = MDState.TEXT;
                        output.append_char(current);
                    }
                }else{
                    state = MDState.TEXT;
                    output.append_html("span", bold, italic);
                    output.append_char(current);
                }
            case MDState.HEADER: 
                if(current == '\n'){
                    DString temp;
                    temp.new_init();
                    temp.appendf("</h%d>", headerSize);
                    output.append(temp.str_view());
                    temp.free();
                    if(bullets){
                        output.append("</li>");
                    }
                    state = START_OF_LINE;
                }
                if(current == '\r') continue;
                output.append_char(current);
            case MDState.TEXT: 
                if(current == '\n'){
                    state = START_OF_LINE;
                    output.append("</span>");
                    if(bullets){
                        output.append("</li>");
                    }
                }else if(current == '*') {
                    usz stars = stream.count('*') + 1;
                    if(stars == 1 || stars == 3){
                        italic = !italic;
                    }
                    if(stars == 2){
                        bold = !bold;
                    }
                    output.append("</span>");
                    output.append_html("span", bold, italic);
                }else{
                    if(current == '\r') continue;
                    output.append_char(current);
                }
            case MDState.BULLET_POINT: 
                console::log("BULLET_POINT");
                if(current == '\n'){
                    if(bullets){
                        output.append("</li>");
                    }
                    state = START_OF_LINE;
                }else if(current == '*') {
                    usz stars = stream.count('*') + 1;
                    if(stars == 1 || stars == 3){
                        italic = !italic;
                    }
                    if(stars == 2){
                        bold = !bold;
                    }
                    if(bold || italic) {
                        output.append_html("span", bold, italic);
                    }else{
                        output.append("</span>");
                    }
                }else{
                    if(current == '\r') continue;
                    output.append_char(current);
                }
            default: 
            console::log("Default");
            output.append_char(current);
        }
    }
    Html md;
    md.size = output.len();
    md.data = allocator::new_array(allocator::heap(),char, md.size);
    console::log("Output: %s", output);
    md.data[0..md.size-1] = output.str_view()[0..md.size-1];
    return md;
}

macro void DString.append_html(&dstr, String component_name, bool is_bold, bool is_italic){
    dstr.appendf("<%s", component_name);
    if(is_bold || is_italic){
         dstr.append(" style=\"");
         if(is_bold){
            dstr.append("font-weight: bold; ");
         }
         if(is_italic){
            dstr.append("font-style: italic; ");
         }
         dstr.append("\"");
    }
    dstr.append_char('>');
}