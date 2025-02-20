module website;
import js::console;

fn void main() @wasm @extern("main"){
    console::log("Hello %s!", "World");
}

    // String str = (String) buffer[0..buffer_sz];
    // console::log((String) buffer[0..buffer_sz]);
fn char* md_to_html(char* buffer, usz buffer_sz, int* size) @wasm @extern("md_to_html") {
    // for(int i = 0; i < buffer_sz; i++) console::log("Hi! %c|%d wew", buffer[i],  buffer[i]);
    int index;
    DString dStr;
    dStr.new_init();
    defer dStr.free();
    dStr.append("<span>");
    while(buffer_sz >= index){
        if(buffer[index] == '#'){
            dStr.append("</span>");
            int hCount = 0;
            while(buffer[index] == '#'){hCount++; index++;}

            if(buffer[index++] != ' '){
                console::log("TODO: Handle improper formating!");
                index--;
            }
            int endIndex = index;
            while(!(buffer_sz >= endIndex) || buffer[endIndex] != '\n'){
                endIndex++;
            }
            dStr.appendf("<h%d>%s</h%d> ", hCount,(String) buffer[index..endIndex-1], hCount);
            index = endIndex;
            dStr.append("<span>");
        }
        else{
            // int endIndex = index;
            // while(!(buffer_sz >= endIndex) && buffer[endIndex] != '\n'){
            //     endIndex++;
            // }
            // dStr.appendf("<span>%s</span> ", (String) buffer[index..endIndex-1]);
            // index = endIndex;
            dStr.append_char(buffer[index]);
            index++;
        }
        // index++;
    }
    *size = (int) dStr.len();
    char* out = allocator::new_array(allocator::heap(),char, *size);
    out[0..(*size)] = dStr.str_view() [0..(*size)];
    console::log("Input: %s", (String)buffer[0..buffer_sz]);
    console::log("Output: %s", dStr);
    return out;
} 

fn void* malloc(uint size) @wasm @extern("malloc") {
    return allocator::malloc(allocator::heap(), size);
}

fn void set(char* buffer, uint index, char value) @wasm @extern("set") {
    buffer[index] = value;
}

fn void free(void* data) @wasm @extern("free") {
    allocator::free(allocator::heap(), data);
}

module js::console;
import std::io;

fn void log(String format, args...){
    @pool(){
        DString str = dstring::temp_with_capacity(format.len + args.len * 8);
        str.appendf(format, ...args);
        String ret_str = str.str_view().tcopy();
        $if env::WASM_NOLIBC:
            write(ret_str.ptr, ret_str.len);
        $else 
            io::printn(ret_str);
        $endif
    };
}

extern fn void write(void *buffer, usz buffer_sz) @extern("console_log");
