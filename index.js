let wasm = null;
window.onload = async () => {
    wasm = await startWasm("./out.wasm");
    wasm.main();
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

        let buffer = this.textContent;
        buffer = buffer.trim();
        const bufferLen = buffer.length;
        const wasmStr = wasm.malloc(bufferLen * 8); //buffer size of textContent, to pass textContent to WASM.
        for(let i = 0; i < bufferLen; i++){
            wasm.set(wasmStr, i, buffer[i].charCodeAt(0));
        }
        const wSize = wasm.malloc(32); //1 int ptr
        const outPtr = wasm.md_to_html(wasmStr, bufferLen, wSize);
        const outSize = new Uint8ClampedArray(wasm.memory.buffer, wSize, 1);
        const outText = new TextDecoder().decode(new Uint8ClampedArray(wasm.memory.buffer, outPtr, outSize));
        // console.log(outText);
        div.innerHTML = outText;
        wasm.free(wasmStr);
        wasm.free(wSize);
        wasm.free(outPtr);
    }
}