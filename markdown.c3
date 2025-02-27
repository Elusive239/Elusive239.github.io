module markdown;
import html;
import js::console;
import std::io;
import std::io::file;

fn void main() @if(!env::WASM_NOLIBC){
    String testFile = (String) file::load_new("./test.md", allocator::heap())!!;
    // console::log("Loaded!");
    uint outSize;
    char* output = html::to_html(testFile.ptr, testFile.len, &outSize);
    // console::log("%s", (String)output[0..outSize]);
    file::save("testOut.html", output[:outSize])!!;
    testFile.free();
    allocator::free(allocator::heap(), output);
}

fn char* js_md_to_html(char* buffer, uint buffer_sz, int* size) @wasm @extern("js_md_to_html") {
    ByteReader byteBuffer;
    byteBuffer.init(buffer[0..buffer_sz]);
    console::log("Input: %s", (String) byteBuffer.bytes);
    Html md = init_parse(&byteBuffer);// md_stream_to_html(&byteBuffer);
    *size = (int) md.size;
    return md.data;
} 

struct Html{
    char* data;
    uint size;
}

macro char! InStream.peek(&self){
    char! ret = self.read_byte();
    self.pushback_byte()!!;
    return ret;
}

macro uint InStream.count(&self, char c){
    uint count;
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

struct MDStateMachine{
    inline DString output;
    MDState state;
    bool bold;
    bool italic;
    bool bullets;
    uint headerSize;
    InStream stream;
}

macro MDStateMachine make(InStream stream){
    MDStateMachine info = MDStateMachine{};
    info.output.new_init();
    info.state = MDState.START_OF_LINE;
    info.stream = stream;
    return info;
}

macro void MDStateMachine.free(&self){
    self.output.free();
}

<*
    @require &(stream.read_byte) != null
    @require &(stream.pushback_byte) != null
    @require &(stream.available) != null
*>
fn Html md_stream_to_html(InStream stream) @wasm @extern("md_stream_to_html"){
    //String font_weight; //= starCount >= 2 ? "bold" : "normal";
    //String font_style ; //= starCount == 1 || starCount == 3 ? "italic" : "normal";

    MDStateMachine machine = make(stream);
    defer machine.free();
    while(true){
        char! current = machine.stream.read_byte();
        if(catch e = current){
            machine.append("</span>");
            break;
        }
        if(current == '/r' || current == 0) continue;
        switch(machine.state){
            case MDState.START_OF_LINE: 
                start_of_line(&machine, current);
            case MDState.HEADER: 
                header(&machine, current);
            case MDState.TEXT: 
                text(&machine, current);
            case MDState.BULLET_POINT: 
                bullet_point(&machine, current);
            default: 
                console::log("Default");
                machine.append_char(current);
        }
    }
    Html md;
    md.size = (uint) machine.len();
    md.data = allocator::new_array(allocator::heap(),char, md.size);
    console::log("Output: %s", machine.output);
    md.data[0..md.size-1] = machine.str_view()[0..md.size-1];
    return md;
}

fn void start_of_line(MDStateMachine* machine, char current){
    if(current == '#'){
        machine.headerSize = machine.stream.count('#') + 1;
        // console::log("START_OF_LINE, Current: %c", current);
        console::log("%d", machine.headerSize);
        if(machine.stream.available()!! > 0 && machine.stream.peek()!! == ' ' && machine.headerSize <= 6){
            DString temp;
            temp.new_init();
            temp.appendf("h%d", machine.headerSize);
            machine.append_html(temp.str_view(),machine.bold, machine.italic);
            temp.free();
            machine.state = MDState.HEADER;
        }else{
            int t = (int) machine.headerSize;
            for(; t; t--){
                machine.append_char('#');
            }   
            machine.state = MDState.TEXT;
        }
    }else if (current == '-' || current == '*'){
        if(machine.stream.peek()!! == ' '){
            machine.stream.read_byte()!!;
            if(!machine.bullets){
                machine.append_html("ul",false, false);
            }
            machine.append_html("li", false, false);
            machine.bullets = true;
            machine.state = MDState.BULLET_POINT;
        }else if(current == '*') {
            if(machine.bullets){
                machine.append("</ul>");
                machine.bullets = false;
            }
            set_font_settings(machine);
            machine.append("</span>");
            machine.append_html("span", machine.bold, machine.italic);
            machine.state = MDState.TEXT;
        }
        else{
            machine.append_char(current);
            machine.state = MDState.TEXT;
        }
    }else{
        machine.append_html("span", machine.bold, machine.italic);
        machine.append_char(current);
        machine.state = MDState.TEXT;
    }
}

macro void set_font_settings(MDStateMachine* machine){
    uint stars = machine.stream.count('*') + 1;

    if(stars > 6){
        for(int i = 0; i < stars - 6; i++) machine.stream.pushback_byte()!!;
    }
    
    machine.italic = stars == 1 || stars >= 3 ? !machine.italic : machine.italic;
    machine.bold = stars >= 2 ? !machine.bold : machine.bold;
}

fn void header(MDStateMachine* machine, char current){
    if(current == '\n'){
        DString temp;
        temp.new_init();
        temp.appendf("</h%d>", machine.headerSize);
        machine.append(temp.str_view());
        temp.free();
        if(machine.bullets){
            machine.append("</li>");
        }
        machine.state = START_OF_LINE;
    }
    if(current == '\r') return;;
    machine.append_char(current);
}

fn void text(MDStateMachine* machine, char current){
    if(current == '\n'){
        machine.append("</span>");
        if(machine.bullets){
            machine.append("</li>");
        }
        machine.state = MDState.START_OF_LINE;
    }else if(current == '*') {
        set_font_settings(machine);
        machine.append("</span>");
        machine.append_html("span", machine.bold, machine.italic);
    }else{
        if(current == '\r') return;
        machine.append_char(current);
    }
}
fn void bullet_point(MDStateMachine* machine, char current){
    if(current == '\n'){
        if(machine.bullets){
            machine.append("</li>");
        }
        machine.state = START_OF_LINE;
    }else if(current == '*') {
        set_font_settings(machine);
        
        if(machine.bold || machine.italic) {
            machine.append_html("span", machine.bold, machine.italic);
        }else{
            machine.append("</span>");
        }
        return;
    }else{ 
        if(current == '\r') return;
        machine.append_char(current);
    }
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

fn Html init_parse(InStream stream){
    MDStateMachine machine = make(stream);
    defer machine.free();
    Html md = {};
    do_parse(&machine);//md_stream_to_html(&byteBuffer);
    md.size = (int) machine.len();
    md.data[0..md.size-1] = machine.str_view()[0..md.size-1];
    return md;
}

fn void do_parse(MDStateMachine* machine){
    while(true){
        char! current = machine.stream.read_byte();
        if(catch e = current){
            return;
        }
        if(current == '/r' || current == 0) return;
        if(current == '\n'){
            machine.state = MDState.START_OF_LINE;
            return;
        }
        switch(machine.state){
            case MDState.START_OF_LINE:
                if(current == '*'){
                    char! next = machine.stream.peek();
                    if(try next){
                        if(next == ' '){
                            machine.stream.read_byte()!!;
                            machine.state = MDState.TEXT;
                            do_bullet_list(machine);
                        }else{
                            set_font_settings(machine);
                            do_span(machine);
                        }
                    }
                }else if(current == '-'){
                    char! next = machine.stream.peek();
                    if(try next){
                        if(next == ' '){
                            machine.state = MDState.BULLET_POINT;
                            do_parse(machine);
                        }else{
                            machine.stream.pushback_byte()!!;
                            machine.state = MDState.TEXT;
                            do_parse(machine);
                        }
                    }
                }else if(current == '#'){
                    machine.stream.pushback_byte()!!;
                    machine.state = MDState.HEADER;
                    do_parse(machine);
                }
                // start_of_line(&machine, current);
            case MDState.HEADER:
                // header(&machine, current);
                machine.state = MDState.TEXT;
                do_header(machine);
            case MDState.TEXT:
                machine.output.append_char(current);
                // text(&machine, current);
            case MDState.BULLET_POINT: 
                machine.state = MDState.TEXT;
                do_bullet_list(machine);
                // bullet_point(&machine, current);
            default: 
                unreachable("UNIMPLEMENTED STATE!");
        }
    }
}

fn void do_span(MDStateMachine* machine){
    machine.state = MDState.TEXT;
    machine.append("<span>");
    bool bold = machine.bold;
    bool italic = machine.italic;
    if(bold) machine.append("<strong>");
    if(italic) machine.append("<em>"); 
    //call parser function...
    if(bold) machine.append("</strong>");
    if(italic) machine.append("</em>"); 
    machine.append("</span>");
}

fn void do_header(MDStateMachine* machine){
    uint hSize = machine.stream.count('#') +1;

    if(hSize > 6){
        for(;hSize; hSize--) machine.append_char('#');
        do_span(machine);
        return;
    }

    machine.appendf("<h%d>", hSize);
    do_span(machine);
    machine.appendf("</h%d>", hSize);
}

fn void do_bullet_list(MDStateMachine* machine){
    machine.append("<ul>");
    while(machine.bullets){ 
        machine.append("<li>");
        do_span(machine);
        machine.append("</li>");
        if(0 == 0) break;
    }
    machine.append("</ul>");
}