#include <elf.h>
#include <link.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include "libc.h"
#include "syscall.h"

#ifdef VDSO_USEFUL

#if ULONG_MAX == 0xffffffff
typedef Elf32_Ehdr Ehdr;
typedef Elf32_Phdr Phdr;
typedef Elf32_Sym Sym;
typedef Elf32_Verdef Verdef;
typedef Elf32_Verdaux Verdaux;
#else
typedef Elf64_Ehdr Ehdr;
typedef Elf64_Phdr Phdr;
typedef Elf64_Sym Sym;
typedef Elf64_Verdef Verdef;
typedef Elf64_Verdaux Verdaux;
#endif

static int checkver(Verdef *def, int vsym, const char *vername, char *strings)
{
	vsym &= 0x7fff;
	for (;;) {
		if (!(def->vd_flags & VER_FLG_BASE)
		  && (def->vd_ndx & 0x7fff) == vsym)
			break;
		if (def->vd_next == 0)
			return 0;
		def = (Verdef *)((char *)def + def->vd_next);
	}
	Verdaux *aux = (Verdaux *)((char *)def + def->vd_aux);
	return !strcmp(vername, strings + aux->vda_name);
}

#define OK_TYPES (1<<STT_NOTYPE | 1<<STT_OBJECT | 1<<STT_FUNC | 1<<STT_COMMON)
#define OK_BINDS (1<<STB_GLOBAL | 1<<STB_WEAK | 1<<STB_GNU_UNIQUE)

void *__vdsosym(const char *vername, const char *name)
{
	size_t i;
	for (i=0; libc.auxv[i] != AT_SYSINFO_EHDR; i+=2)
		if (!libc.auxv[i]) return 0;
	if (!libc.auxv[i+1]) return 0;
	Ehdr *eh = (void *)libc.auxv[i+1];
	Phdr *ph = (void *)((char *)eh + eh->e_phoff);
	size_t *dynv=0, base=-1;
	for (i=0; i<eh->e_phnum; i++, ph=(void *)((char *)ph+eh->e_phentsize)) {
		if (ph->p_type == PT_LOAD)
			base = (size_t)eh + ph->p_offset - ph->p_vaddr;
		else if (ph->p_type == PT_DYNAMIC)
			dynv = (void *)((char *)eh + ph->p_offset);
	}
	if (!dynv || base==(size_t)-1) return 0;

	char *strings = 0;
	Sym *syms = 0;
	Elf_Symndx *hashtab = 0;
	uint32_t *gnu_hashtab = 0;
	uint16_t *versym = 0;
	Verdef *verdef = 0;

	for (i=0; dynv[i]; i+=2) {
		void *p = (void *)(base + dynv[i+1]);
		switch(dynv[i]) {
		case DT_STRTAB: strings = p; break;
		case DT_SYMTAB: syms = p; break;
		case DT_HASH: hashtab = p; break;
		case DT_GNU_HASH: gnu_hashtab = p; break;
		case DT_VERSYM: versym = p; break;
		case DT_VERDEF: verdef = p; break;
		}
	}

	if (!strings || !syms || (!hashtab && !gnu_hashtab)) return 0;
	if (!verdef) versym = 0;

	/* Determine the number of dynamic symbols to scan. The SysV hash
	 * table records it directly (nchain == symbol count). Modern kernels
	 * emit only a GNU hash table for the vDSO, which has no explicit
	 * count, so derive the highest symbol index by walking the buckets
	 * and following the longest chain to its terminator. */
	size_t nsym;
	if (hashtab) {
		nsym = hashtab[1];
	} else {
		uint32_t nbuckets = gnu_hashtab[0];
		uint32_t symoffset = gnu_hashtab[1];
		uint32_t bloom_size = gnu_hashtab[2];
		size_t *bloom = (void *)(gnu_hashtab + 4);
		uint32_t *buckets = (uint32_t *)(bloom + bloom_size);
		uint32_t *chain = buckets + nbuckets;
		uint32_t last = 0;
		for (uint32_t b = 0; b < nbuckets; b++)
			if (buckets[b] > last) last = buckets[b];
		if (last < symoffset) {
			/* No symbols are present in the hash chains. */
			nsym = symoffset;
		} else {
			/* Follow the chain from the highest bucket head until
			 * the terminating entry (low bit set) is reached. */
			while (!(chain[last - symoffset] & 1)) last++;
			nsym = last + 1;
		}
	}

	for (i=0; i<nsym; i++) {
		if (!(1<<(syms[i].st_info&0xf) & OK_TYPES)) continue;
		if (!(1<<(syms[i].st_info>>4) & OK_BINDS)) continue;
		if (!syms[i].st_shndx) continue;
		if (strcmp(name, strings+syms[i].st_name)) continue;
		if (versym && !checkver(verdef, versym[i], vername, strings))
			continue;
		return (void *)(base + syms[i].st_value);
	}

	return 0;
}

#endif
