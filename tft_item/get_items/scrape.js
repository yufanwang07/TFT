(async function() {
    window.scrapedTFTItems = {};
    window.filteredOutItems = {};

    const tabNames = ["Basic", "Combined", "Anima", "Psionic", "Radiant", "Non-Craftable", "Consumable", "Artifact"];
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

    function downloadFile(content, fileName, contentType) {
        const a = document.createElement("a");
        const file = new Blob([content], { type: contentType });
        a.href = URL.createObjectURL(file);
        a.download = fileName;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(a.href);
    }

    function scrollEverything(scrollTopValue) {
        window.scrollTo(0, scrollTopValue);
        const containers = document.querySelectorAll('div, main, section');
        containers.forEach(el => {
            const style = window.getComputedStyle(el);
            if (el.scrollHeight > el.clientHeight && (style.overflowY === 'auto' || style.overflowY === 'scroll')) {
                el.scrollTop = scrollTopValue;
            }
        });
    }

    function getScrollPosition() {
        let maxScroll = window.scrollY || document.documentElement.scrollTop;
        const containers = document.querySelectorAll('div, main, section');
        containers.forEach(el => {
            const style = window.getComputedStyle(el);
            if (el.scrollHeight > el.clientHeight && (style.overflowY === 'auto' || style.overflowY === 'scroll')) {
                maxScroll = Math.max(maxScroll, el.scrollTop);
            }
        });
        return maxScroll;
    }

    function findTabElement(tabName) {
        const primarySelectors = 'button, a, [role="button"], [role="tab"]';
        let elements = Array.from(document.querySelectorAll(primarySelectors));
        let match = elements.find(el => el.textContent.trim().toLowerCase() === tabName.toLowerCase());
        
        if (!match) {
            const allElements = Array.from(document.querySelectorAll('div, span, p'));
            match = allElements.find(el => {
                const text = el.textContent.trim();
                return text.toLowerCase() === tabName.toLowerCase() && text.length === tabName.length;
            });
        }
        return match;
    }

    function checkAndCleanItemName(text) {
        if (!text) return { valid: false, reason: "No text found in parent or grandparent" };
        
        const cleanedText = text.trim().replace(/\s+/g, ' ');
        
        if (cleanedText.length < 3) {
            return { valid: false, reason: `Too short (${cleanedText.length} chars)`, text: cleanedText };
        }
        if (cleanedText.length > 35) {
            return { valid: false, reason: `Too long (${cleanedText.length} chars)`, text: cleanedText };
        }
        
        if (cleanedText.endsWith('.')) {
            return { valid: false, reason: "Ends with a period (indicates a description sentence)", text: cleanedText };
        }
        
        const descriptionKeywords = [
            'occur', 'grant', 'gain', 'holder', 'every', 'once', 'based on', 
            'user:', 'users:', 'combat', 'unequip', 'disappears', 
            'increases', 'reduces', 'heal', 'damage to', 'additional bonus'
        ];
        
        const lowerText = cleanedText.toLowerCase();
        for (let keyword of descriptionKeywords) {
            if (lowerText.includes(keyword)) {
                return { valid: false, reason: `Contains description keyword: "${keyword}"`, text: cleanedText };
            }
        }
        
        return { valid: true, text: cleanedText };
    }

    function scrapeCurrentTab() {
        let addedCount = 0;
        const allImages = document.querySelectorAll('img');
        
        allImages.forEach(img => {
            let src = img.getAttribute('data-src') || img.getAttribute('src') || img.src;
            if (!src) return;

            if (src.includes('_next/image')) {
                try {
                    const urlParams = new URLSearchParams(src.split('?')[1]);
                    const originalUrl = urlParams.get('url');
                    if (originalUrl) {
                        src = originalUrl;
                    }
                } catch (e) {}
            }
            
            if (src && !src.startsWith('http')) {
                src = new URL(src, window.location.origin).href;
            }

            const isItemImg = src.includes('game-items') || src.includes('item') || src.includes('equipment') || src.includes('artifact');
            if (!isItemImg) return;

            let rawName = "";
            if (img.parentElement) {
                const parentText = img.parentElement.textContent.trim();
                if (parentText.length >= 3) {
                    rawName = parentText;
                } else if (img.parentElement.parentElement) {
                    const gpText = img.parentElement.parentElement.textContent.trim();
                    if (gpText.length >= 3) {
                        rawName = gpText;
                    }
                }
            }

            const nameCheck = checkAndCleanItemName(rawName);
            
            if (!nameCheck.valid) {
                if (nameCheck.text && nameCheck.text.trim().length > 0) {
                    const loggedText = nameCheck.text.trim();
                    const key = `${loggedText}_${src}`;
                    if (!window.filteredOutItems[key]) {
                        window.filteredOutItems[key] = {
                            RawText: loggedText,
                            ImageUrl: src,
                            Reason: nameCheck.reason
                        };
                    }
                }
                return;
            }

            const name = nameCheck.text;
            if (name && src && !window.scrapedTFTItems[name]) {
                window.scrapedTFTItems[name] = src;
                addedCount++;
            }
        });

        return addedCount;
    }

    async function scrollAndScrapeTab(tabName) {
        scrollEverything(0);
        await sleep(400);
        
        let lastScrollPos = -1;
        let currentScroll = 0;
        let addedTotal = 0;
        
        while (true) {
            const added = scrapeCurrentTab();
            addedTotal += added;
            
            currentScroll += 450;
            scrollEverything(currentScroll);
            await sleep(250);
            
            const currentScrollPos = getScrollPosition();
            
            if (currentScrollPos === lastScrollPos) {
                const finalAdded = scrapeCurrentTab();
                addedTotal += finalAdded;
                break;
            }
            
            lastScrollPos = currentScrollPos;
        }
        
        scrollEverything(0);
        await sleep(300);
        
        return addedTotal;
    }

    console.log("Starting scraper...");

    for (let i = 0; i < tabNames.length; i++) {
        const tab = tabNames[i];
        const tabEl = findTabElement(tab);
        if (tabEl) {
            const clickable = tabEl.closest('button, a, [role="button"], [role="tab"]') || tabEl;
            clickable.click();
            await sleep(2500); 
            await scrollAndScrapeTab(tab);
        } else {
            await scrollAndScrapeTab(tab);
        }
        await sleep(500);
    }

    const itemsArray = Object.entries(window.scrapedTFTItems).map(([name, url]) => ({
        Name: name,
        ImageUrl: url
    }));

    const filteredOutArray = Object.values(window.filteredOutItems);

    console.log("Scraping completed. Found " + itemsArray.length + " items.");

    if (itemsArray.length > 0) {
        const jsonContent = JSON.stringify(itemsArray, null, 2);
        downloadFile(jsonContent, "tft_items.json", "application/json");

        const csvRows = ["Name,Image URL"];
        itemsArray.forEach(item => {
            const escapedName = item.Name.replace(/"/g, '""');
            csvRows.push(`"${escapedName}","${item.ImageUrl}"`);
        });
        const csvContent = csvRows.join("\n");
        downloadFile(csvContent, "tft_items.csv", "text/csv;charset=utf-8;");

        if (filteredOutArray.length > 0) {
            const filteredOutContent = JSON.stringify(filteredOutArray, null, 2);
            downloadFile(filteredOutContent, "filtered_out.json", "application/json");
        }
    } else {
        console.error("No items found.");
    }
})();