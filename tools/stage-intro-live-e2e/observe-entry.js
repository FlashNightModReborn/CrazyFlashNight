'use strict';
// The origin pointer is durable before the new book slot's first stage save.
// Observe that owned transition passively; never admit a missing/foreign run.
async function observeOwnedEntry(options) {
    const now=options.now||Date.now,wait=options.wait||((ms)=>new Promise(resolve=>setTimeout(resolve,ms)));
    const deadline=now()+45000;
    while(true) {
        const status=await options.readStatus(),origin=options.readOrigin(),active=origin.ext?.bookshelf?.active;
        let book;
        if(active?.slot) {
            if(active.bookId!==options.bookId||active.originSlot!==options.originSlot||!/^bookrun_[a-f0-9]{24}$/.test(active.slot))
                throw Error('Unexpected affiliated book identity; stopping observation');
            try{book=options.readBook(active.slot);}
            catch(error){
                if(error.code!=='ENOENT')throw error;
                const slot=status?.saveRuntime?.savePath;
                if(slot!==options.originSlot&&slot!==active.slot)throw Error('Missing book file with foreign runtime ownership');
                if(now()>=deadline)throw Error('Owned book entry did not finish creating its first save within 45 seconds');
                await wait(200);continue;
            }
            const run=book.ext?.bookRun;
            if(run?.bookId!==options.bookId||run.originSlot!==options.originSlot||run.slot!==active.slot
                    ||options.routeId&&run.routeId!==options.routeId)throw Error('Affiliated run does not match the production origin/route');
        }
        const runtimeSlot=status?.saveRuntime?.savePath;
        if(status?.saveRuntime?.loaded!==true&&[options.originSlot,active?.slot,...(options.affiliatedSlots||[])].includes(runtimeSlot)) {
            if(now()>=deadline)throw Error('Owned runtime did not finish its save switch within 45 seconds');
            await wait(200);continue;
        }
        return {status,origin,active,book};
    }
}
module.exports={observeOwnedEntry};
