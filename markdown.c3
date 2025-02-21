module markdown;
import js::console;
import std::io;
import std::io::file;

fn void main() @if(!env::WASM_NOLIBC){
    String testFile = (String) file::load_new("./test.md", allocator::heap())!!;
    // console::log("Loaded!");
    int outSize;
    char* output = md_to_html(testFile.ptr, testFile.len, &outSize);
    // console::log("%s", (String)output[0..outSize]);
    file::save("testOut.html", output[:outSize])!!;
    testFile.free();
    allocator::free(allocator::heap(), output);
}

fn char* md_to_html(char* buffer, usz buffer_sz, int* size) @wasm @extern("md_to_html") {
    // for(int i = 0; i < buffer_sz; i++) console::log("Hi! %c|%d wew", buffer[i],  buffer[i]);
    int index;
    DString dStr;
    dStr.new_init();
    defer dStr.free();
    dStr.append("<span>");
    while(buffer_sz > index){
        if(buffer[index] == '#'){
            dStr.append("</span>");
            int hCount = 0;
            while(buffer[index] == '#'){hCount++; index++;}

            if(buffer[index++] != ' '){
                console::log("TODO: Handle improper header formating!");
                index--;
            }
            int endIndex = index;
            while(!(buffer_sz >= endIndex) || buffer[endIndex] != '\n'){
                endIndex++;
            }
            dStr.appendf("<h%d>%s</h%d> ", hCount,(String) buffer[index..endIndex-1], hCount);
            index = endIndex;
            dStr.append("<br><span>");
        }
        else if (buffer[index] == '*'){
            dStr.append("</span>");
            int starCount = 0;
            while(!(buffer_sz >= index) || buffer[index] == '*'){
                starCount++; 
                index++;
            }
            // console::log("Current: %c", buffer[index]);
            int endIndex = index;
            while((buffer[endIndex] != '*')){
                endIndex++;
            }
            String contents = (String)buffer[index..endIndex-1];
            index = endIndex;
            int endStars = 0;
            while(!(buffer_sz >= index) || buffer[index] == '*'){endStars++; index++;}
            console::log("Start: %d End: %d", starCount, endStars);
            if(starCount == endStars){
                //italic
                //bold
                //italic and bold
                String font_weight = starCount >= 2 ? "bold" : "normal";
                String font_style = starCount == 1 || starCount == 3 ? "italic" : "normal";
                dStr.appendf("<span style=\"font-weight: %s; font-style: %s;\">%s</span>", font_weight, font_style, contents);
            }else{
                console::log("TODO: Handle improper italic formating!");
            }
            dStr.append("<span>");
            index++;
        } else if (buffer[index] == '\n' && buffer[index-2] == '\n'){
            while(buffer[index] == '\n'){
                index++;
            }
            dStr.append("</span><br><span>");
        }
        // else if (buffer[index] == '\n'){
        //     while(buffer[index] == '\n'){
        //         index++;
        //     }
        //     dStr.append("<br><br/>");
        // }else if (buffer[index] == '\r'){
        //     index++;
        // }
        else{
            dStr.append_char(buffer[index]);
            index++;
        }
        // index++;
    }
    *size = (int) dStr.len();

    char* out = allocator::new_array(allocator::heap(),char, *size);

    out[0..(*size)-1] = dStr.str_view() [0..(*size)-1];
    
    // console::log("Input: %s", (String)buffer[0..buffer_sz]);
    // console::log("Output: %s", dStr);
    return out;
} 