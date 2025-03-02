let wasm = null;
window.onload = async () => {
    wasm = await startWasm("./out.wasm");
    // wasm.main();
    window.customElements.define('noir-down', MarkDown);
};

async function startWasm(url) {
    const importObject = {
        env: { 
            console_log: (buffer, bufferLen) => console.log(new TextDecoder().decode(new Uint8ClampedArray(wasm.memory.buffer, buffer, bufferLen))),
            // rand: () => Math.random(),
        },
    };      
    const wasm = await WebAssembly.instantiateStreaming(await fetch(url), importObject).then(
        (wasm_stream) => {
            return {
                stream: wasm_stream,
                memory: wasm_stream.instance.exports.memory ,
                ...wasm_stream.instance.exports,
            };
        }
    );
    wasm._initialize();
    return wasm;
}


class MarkDown extends HTMLElement{
    constructor(){
        super();
        const shadowRoot = this.attachShadow({mode: 'closed'});
        let div = document.createElement('div');
        shadowRoot.append(div);
        const fname = this.getAttribute("src") || undefined;
        if(fname === undefined ){
            console.error("'src' attribute never defined!");
            return;
        }

        fetch(fname)
        .then(response => response.text())
        .then(text => {
            let buffer = text;
            buffer = buffer.trim();
            const bufferLen = buffer.length;
            const wasmStr = wasm.wasm_malloc(bufferLen * 8); //buffer size of textContent, to pass textContent to WASM.
            for(let i = 0; i < bufferLen; i++){
                wasm.wasm_set(wasmStr, i, buffer[i].charCodeAt(0));
            }
            // console.log("%d", wasm.size_of_usz());
            const wSize = wasm.wasm_malloc(wasm.size_of_uint()); //1 int ptr
            const outPtr = wasm.wasm_to_html(wasmStr, bufferLen, wSize);
            const outSize = new Uint32Array(wasm.memory.buffer, wSize, 1);
            const outText = new TextDecoder().decode(new Uint8ClampedArray(wasm.memory.buffer, outPtr, outSize[0]));
            // console.log("OutText: ", outText);
            // console.log("OutText as Array : ", Array.from(outText));
            // console.log("Size: ", Array.from(outSize));
            div.innerHTML = outText;
            wasm.wasm_free(wasmStr);
            wasm.wasm_free(wSize);
            wasm.wasm_free(outPtr);
        });
    }
}