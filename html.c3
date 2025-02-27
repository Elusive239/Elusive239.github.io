module html;
import std::io;
import std::collections;
import js::console;

def HTMLComponentList = List(<HTMLComponent>);

struct HTMLComponent{
    String tag;
    DString content;
    usz headerSize;
    HTMLComponentList inner;
}

struct HtmlDocument{
    char* data;
    usz size;
}

fn void HTMLComponent.add(&self, HTMLComponent component){
    self.inner.push(component);
}

fn String HTMLComponent.to_text(&self){
    DString dstr;
    defer dstr.free();
    dstr.new_init();
    for(int i = 0; i < self.inner.len(); i++){
        self.inner[i].recursive_to_text(&dstr);
        dstr.append_char('\n');
    }
    return dstr.copy_str();
}

fn void HTMLComponent.recursive_to_text(&self, DString* dstr){
    dstr.appendf("<%s>",self.tag);
    dstr.append(self.content);
    for(int i = 0; i < self.inner.len();i++ ){
        self.inner[i].recursive_to_text(dstr);
    }
    dstr.appendf("</%s>",self.tag);
}

fn char* to_html(char* buffer, usz buffer_sz, int* out_size) @wasm @extern("to_html"){
    ByteReader byteBuffer;
    byteBuffer.init(buffer[0..buffer_sz]);
    
    HtmlDocument doc = stream_to_html(&byteBuffer);// md_stream_to_html(&byteBuffer);
    *out_size = (int) doc.size;
    return doc.data;
}

fn HtmlDocument stream_to_html(InStream stream){
    HTMLComponent root;

    new_parse_md(&root, stream);

    String out = root.to_text();
    return HtmlDocument{
        .data = out[:out.len],
        .size = out.len
    };
}

/*
    [Refrence im following to get me started again](https://eloquentjavascript.net/1st_edition/chapter6.html#p90fad98)
 1. Split the file into paragraphs by cutting it at every empty line.
 2. Remove the '%' characters from header paragraphs and mark them as headers.
 3. Process the text of the paragraphs themselves, splitting them into normal parts, emphasised parts, and footnotes.
 4. Move all the footnotes to the bottom of the document, leaving numbers1 in their place.
 5. Wrap each piece into the correct HTML tags.
 6. Combine everything into a single HTML document.
*/
fn void new_parse_md(HTMLComponent* current, InStream stream){
    char[1024*2] buffer;
    do{
        usz index = 0;
        {
            while(stream.available()!!){
                char! next = stream.read_byte();
                if(catch next){
                    break;
                } else if (next == '\r'){
                    continue;
                } else if (index -1 > 0 && buffer[index-1] == next && next == '\n'){
                    // console::log("DOUBLE LINE FEED");
                    break;
                }else{
                    buffer[index++] = next;
                }
            }
            // console::log("BUFFER: %s", buffer);
        }

        parse_start(current, &(buffer[0]), index);

    }while(stream.available()!!);
}

fn void parse_start(HTMLComponent* current, char* buffer, usz buffer_sz){
    if(buffer_sz == 0 || buffer[0] == 0) return;

    if(buffer[0].is_blank() || buffer[0].is_space()){
        console::log("%s|%d", buffer[0..buffer_sz],buffer);
        int i = 0;
        while(i<buffer_sz && (buffer[i].is_blank() || buffer[i].is_space())){
            i++;
        }
        buffer = buffer+i;
        buffer_sz = buffer_sz - i;
        console::log("%s|%d", buffer[0..buffer_sz],buffer);
    }

    if('#' == buffer[0]){
        //count '#'
        int i = 0; 
        while(buffer[i] == '#') i++;
        parse_header(current, buffer+i, buffer_sz-i, i);
    }else if ('>' == buffer[0] && ' ' == buffer[1]){
        parse_block_quote(current, buffer+1, buffer_sz-1);
    }else if ('-' == buffer[0] && '-' == buffer[1] && '-' == buffer[2]){
        current.add(HTMLComponent{.tag="hr"});
        parse_start(current, buffer+3, buffer_sz-3);
    }else if (('-' == buffer[0] || '*' == buffer[0]) && ' ' == buffer[1] ){
        parse_unordered_list(current, buffer, buffer_sz, '-' == buffer[0] ? '-' : '*');
    } else if('`' == buffer[0]){
        usz i;
        parse_inline_code(current, buffer, buffer_sz, &i);
        console::log("Parsed %d", i);
        parse_start(current, buffer+i, buffer_sz-i);
    } else {    
        current.make_paragraph();
        usz i =0;
        parse_text( &current.inner[current.inner.len()-1], buffer,buffer_sz, &i);
    }
}

fn void parse_block_quote(HTMLComponent* current, char* buffer, usz buffer_sz){
    current.add(HTMLComponent{.tag="blockquote"});
    HTMLComponent* next_comp = &current.inner[current.inner.len()-1];
    parse_line(next_comp, buffer, buffer_sz);
}

fn void parse_header(HTMLComponent* current, char* buffer, usz buffer_sz, int hash_count){
    current.make_header(hash_count);
    HTMLComponent* next_comp = &current.inner[current.inner.len()-1];
    parse_line(next_comp, buffer, buffer_sz);
}

macro void parse_line(HTMLComponent* current, char* buffer, usz buffer_sz){
    
    for(usz i = 0; i < buffer_sz; i++){
        if(buffer[i] == 0){
            continue;
        }else if (buffer[i] == '\n'){
            return;
        }
        else if(buffer[i] == '*'){
            parse_emphasis(current, buffer, buffer_sz, &i);
        }
        else if(buffer[i] == '`'){
            parse_inline_code(current, buffer, buffer_sz, &i);
        }
        else{
            current.content.append_char(buffer[i]);
        }
    }
}

fn void parse_unordered_list(HTMLComponent* current, char* buffer, usz buffer_sz, char bp_check){
    assert(buffer[0] == bp_check);
    assert(buffer[1] == ' ');
    HTMLComponent ul = HTMLComponent{.tag="ul"};
    HTMLComponent next;
    for(usz i = 0; i < buffer_sz; i++){
        if(buffer[i] == bp_check && i+2 < buffer_sz && buffer[i+1] == ' '){
            if(next.tag != ""){
                ul.add(next);
            }

            next = HTMLComponent{.tag="li"};
            i+=1;
            continue;
        }

        if(buffer[i] == 0){
            continue;
        }else if (buffer[i] == '\n'){
            return;
        }
        else if(buffer[i] == '*'){
            parse_emphasis(&next, buffer, buffer_sz, &i);
        }
        else if(buffer[i] == '`'){
            parse_inline_code(&next, buffer, buffer_sz, &i);
        }
        else{
            next.content.append_char(buffer[i]);
        }
    }
    if(next.tag != "") ul.add(next);
    current.add(ul);
}

fn void parse_text(HTMLComponent* current, char* buffer, usz buffer_sz, usz* index){
    usz i = *index;
    for(; i < buffer_sz; i++){
        if(buffer[i] == 0){
            continue;
        }
        else if(buffer[i] == '*'){
            parse_emphasis(current, buffer, buffer_sz, &i);
        }else{
            current.content.append_char(buffer[i]);
        }
    }
    *index = i;
}

fn void parse_inline_code(HTMLComponent* current, char* buffer, usz buffer_sz, usz* index){
    assert(buffer[*index] == '`');
    usz i = (*index)+1;
    current.add(HTMLComponent{.tag="code"});
    HTMLComponent* next_comp = &current.inner[current.inner.len()-1];
    while(i < buffer_sz && buffer[i] != '`'){
        next_comp.content.append_char(buffer[i++]);
    }
    *index = i+1;
}

fn void parse_emphasis(HTMLComponent* current, char* buffer, usz buffer_sz, usz* index){
    usz i = *index;
    usz starCount = 0;
    while(buffer[i] == '*') {
        starCount++; 
        i++;
    }
    if(starCount != 2 && starCount > 0) current.content.append("<em>");
    if(starCount >= 2) current.content.append("<strong>");
    while(buffer[i] != '*') {
        current.content.append_char(buffer[i]);
        i++;
    }
    if(starCount >= 2) current.content.append("</strong>");
    if(starCount != 2  && starCount > 0) current.content.append("</em>");
    while(buffer[i] == '*') {
        starCount--; 
        i++;
    }
    assert(starCount == 0);
    *index = i;
}

fn void parse_md(HTMLComponent* current, InStream stream){
    while(true){
        char! next = stream.read_byte();
        if(catch next) return;
        // console::log("Current: %s Char: %c|%d", current.tag, next, next);
        if(next == '\r'|| next == '' || next == '' || next == 0) continue;
        if((current.tag.starts_with("h") || current.tag.starts_with("li")) && next == '\n'){
            return;
        }
        if(next == '#'){
            usz headerCount = 0;
            char! headerTrack;
            do{
                headerTrack = (stream.read_byte());
                if(catch headerTrack) break;
                headerCount++;
            }while(headerTrack!! == '#');
            stream.pushback_byte()!!;
            current.make_header(headerCount);
            parse_md(&current.inner[current.inner.len()-1], stream);
        } else if(next == '-'){
            usz dashCount = 1;
            char! tracker = stream.read_byte();
            while(tracker!! == '-'){
                tracker = (stream.read_byte());
                if(catch tracker) {tracker = 0; break;}
                dashCount++;
            }
            stream.pushback_byte()!!;
            if (dashCount == 1 && tracker!!.is_blank()){
                current.make_unordered_list();
                if(current.inner[current.inner.len()-1].tag == "ul"){
                    stream.pushback_byte()!!;
                    stream.pushback_byte()!!;
                }
                parse_md(&current.inner[current.inner.len()-1], stream);
            }else if (dashCount == 3){
                current.make_horizontal_rule();
                continue;
            } else{
                current.content.append_char(next);
                for(int i =0 ; i< dashCount-1; i++)current.content.append_char('-');
            }
        } else if(next == '*'){
            usz starCount = 0;
            char! starTrack;
            do{
                starTrack = (stream.read_byte());
                if(catch starTrack){starTrack = 0; break;}
                starCount++;
            }while(starTrack!! == '*');
            if(starCount == 1 && !starTrack!!.is_alpha()){
                current.make_unordered_list();
                if(current.inner[current.inner.len()-1].tag == "ul"){
                    stream.pushback_byte()!!;
                    stream.pushback_byte()!!;
                }
                parse_md(&current.inner[current.inner.len()-1], stream);
            } else if(starCount == 3 && !starTrack!!.is_alpha() && !(current.tag != "em" || current.tag != "strong")){
                current.make_horizontal_rule();
                continue;
            } else{
                stream.pushback_byte()!!;
                if(current.tag == "strong" && starCount >= 2) return;
                if(current.tag == "em" && (starCount == 1 || starCount == 3)) return;

                current.make_bold_or_italic(starCount);
                switch(starCount){
                    case 1:
                    case 2:
                        parse_md(&current.inner[current.inner.len()-1], stream);
                    case 3: 
                        parse_md(&current.inner[current.inner.len()-1].inner[0], stream);
                        return;
                    default: break;
                }
            }
        } else if (current.tag == ""){
            current.make_paragraph();
            parse_md(&current.inner[current.inner.len()-1], stream);
        } 
        else if (current.tag == "ul" && !next.is_blank()){
            stream.pushback_byte()!!;
            return;
        }
        else if(next == '\n'){
            if(stream.skip_blank_till_character('\n') && current.tag == "p"){
                stream.pushback_byte()!!;
                return;
            }
            // stream.pushback_byte()!!;
            continue;
        }
        else{
            current.content.append_char(next);
        }
    }
}

/*
} else if (current.tag == ""){
    current.make_paragraph();
    parse_md(&current.inner[current.inner.len()-1], stream);
} 
else if (current.tag == "ul" && !next.is_blank()){
    stream.pushback_byte()!!;
    return;
}
else if(next == '\n'){
    if(stream.skip_blank_till_character('\n') && current.tag == "p"){
        stream.pushback_byte()!!;
        return;
    }
    // stream.pushback_byte()!!;
    continue;
}
else{
    current.content.append_char(next);
}
*/


macro bool InStream.skip_blank_till_character(&self, char key){
    do{
        char! c = self.read_byte();
        if(try c) switch(c){
            case key:
                return true;
            case 0:
            case '\r':
            case '\t':
            case '\n':
            case ' ':
                continue;
            default: 
                break;
        }
    }while(self.available()!!);
    self.pushback_byte()!!;
    return false;
}

macro void HTMLComponent.make_horizontal_rule(HTMLComponent* root){
    root.add(HTMLComponent{.tag = "hr"});
}

macro void HTMLComponent.make_paragraph(HTMLComponent* root){
    root.add(HTMLComponent{.tag = "p"});
}

macro void HTMLComponent.make_bold_or_italic(HTMLComponent* root, usz starCount){
    switch(starCount){
        case 0: 
            return;
        return;
        case 1: root.add(HTMLComponent{.tag = "em"});
        case 2: root.add(HTMLComponent{.tag = "strong"});
        case 3:
            HTMLComponent em = HTMLComponent{.tag = "em"};
            em.add(HTMLComponent{.tag = "strong"});
            root.add(em);
        default:
            for(int i =0 ; i < starCount; i++) root.content.append_char('*');
    }
}

macro void HTMLComponent.make_unordered_list(HTMLComponent* root){
    if(root.tag == "ul"){
        root.add(HTMLComponent{
            .inner = {},
            .tag = "li",
        });
    }else{
        HTMLComponent element_root = HTMLComponent{
            .inner = {},
            .tag = "ul",
        };
        root.add(element_root);
    }
}

macro void HTMLComponent.make_header(HTMLComponent* root,usz headerSize){
    DString temp;
    temp.new_init();
    defer temp.free();
    temp.appendf("h%d", headerSize);
    root.add(HTMLComponent{
        .inner = {},
        .tag = temp.copy_str(),
        .headerSize = headerSize
    });
}