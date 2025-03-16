/*
    bfinject - Inject shared libraries into running App Store apps on iOS 11.x < 11.2
    https://github.com/BishopFox/bfinject
*/
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach-o/dyld.h>
#include <objc/runtime.h>
#include <mach/mach.h>
#include <err.h>
#include <mach-o/ldsyms.h>
#include <libkern/OSCacheControl.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/uio.h>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <errno.h>
#include <mach/vm_map.h>
#include <mach-o/dyld_images.h>
#include <mach/task_info.h>
#include <sys/mman.h>
#include <mach/machine.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "SSZipArchive/SSZipArchive.h"
#import "TDDumpDecrypted.h"
#import "TDUtils.h"


kern_return_t
mach_vm_read_overwrite(vm_map_t, mach_vm_address_t, mach_vm_size_t, mach_vm_address_t, mach_vm_size_t *);

kern_return_t 
mach_vm_region(vm_map_read_t target_task, mach_vm_address_t *address, mach_vm_size_t *size, vm_region_flavor_t flavor, vm_region_info_t info, mach_msg_type_number_t *infoCnt, mach_port_t *object_name);


#define swap32(value) (((value & 0xFF000000) >> 24) | ((value & 0x00FF0000) >> 8) | ((value & 0x0000FF00) << 8) | ((value & 0x000000FF) << 24) )

unsigned char *readProcessMemory (mach_port_t proc, mach_vm_address_t addr, mach_msg_type_number_t* size) {
    mach_msg_type_number_t  dataCnt = (mach_msg_type_number_t) *size;
    vm_offset_t readMem;
    
    kern_return_t kr = vm_read(proc, addr, *size, &readMem, &dataCnt);
    
    if (kr) {
        
        return NULL;
    }
    
    return ((unsigned char *) readMem);
}

static kern_return_t
readmem(mach_vm_offset_t *buffer, mach_vm_address_t address, mach_vm_size_t size, vm_map_t targetTask, vm_region_basic_info_data_64_t *info)
{
  // get task for pid
  vm_map_t port = targetTask;
  
  kern_return_t kr;
  mach_msg_type_number_t info_cnt = sizeof (vm_region_basic_info_data_64_t);
  mach_port_t object_name;
  mach_vm_size_t size_info;
  mach_vm_address_t address_info = address;
  kr = mach_vm_region(port, &address_info, &size_info, VM_REGION_BASIC_INFO_64, (vm_region_info_t)info, &info_cnt, &object_name);
  if (kr)
  {
    fprintf(stderr, "[ERROR] mach_vm_region failed with error %d\n", (int)kr);
    return KERN_FAILURE;
  }
  
  /* read memory - vm_read_overwrite because we supply the buffer */
  mach_vm_size_t nread;
  kr = mach_vm_read_overwrite(port, address, size, (mach_vm_address_t)buffer, &nread);
  if (kr)
  {
    fprintf(stderr, "[ERROR] vm_read failed! %d\n", kr);
    return KERN_FAILURE;
  }
  else if (nread != size)
  {
    fprintf(stderr, "[ERROR] vm_read failed! requested size: 0x%llx read: 0x%llx\n", size, nread);
    return KERN_FAILURE;
  }
  return KERN_SUCCESS;
}

int64_t
get_image_size(mach_vm_address_t address, vm_map_t targetTask, uint64_t *vmaddr_slide)
{
  vm_region_basic_info_data_64_t region_info = {0};
    
  struct mach_header header = {0};
  if (readmem((mach_vm_offset_t*)&header, address, sizeof(struct mach_header), targetTask, &region_info))
  {
    printf("Can't read header!\n");
    return -1;
  }
  
  if (header.magic != MH_MAGIC && header.magic != MH_MAGIC_64)
  {
		printf("[ERROR] Target is not a mach-o binary!\n");
    return -1;
  }
  
  int64_t imagefilesize = -1;
  /* read the load commands */
  uint8_t *loadcmds = (uint8_t*)malloc(header.sizeofcmds);
  uint16_t mach_header_size = sizeof(struct mach_header);
  if (header.magic == MH_MAGIC_64)
  {
    mach_header_size = sizeof(struct mach_header_64);
  }
  if (readmem((mach_vm_offset_t*)loadcmds, address+mach_header_size, header.sizeofcmds, targetTask, &region_info))
  {
    printf("Can't read load commands\n");
    free(loadcmds);
    return -1;
  }
  
  /* process and retrieve address and size of linkedit */
  uint8_t *loadCmdAddress = 0;
  loadCmdAddress = (uint8_t*)loadcmds;
  struct load_command *loadCommand    = NULL;
  struct segment_command *segCmd      = NULL;
  struct segment_command_64 *segCmd64 = NULL;
  for (uint32_t i = 0; i < header.ncmds; i++)
  {
    loadCommand = (struct load_command*)loadCmdAddress;
    if (loadCommand->cmd == LC_SEGMENT)
    {
      segCmd = (struct segment_command*)loadCmdAddress;
      if (strncmp(segCmd->segname, "__PAGEZERO", 16) != 0)
      {
        if (strncmp(segCmd->segname, "__TEXT", 16) == 0)
        {
          *vmaddr_slide = address - segCmd->vmaddr;
        }
        imagefilesize += segCmd->filesize;
      }
    }
    else if (loadCommand->cmd == LC_SEGMENT_64)
    {
      segCmd64 = (struct segment_command_64*)loadCmdAddress;
      if (strncmp(segCmd64->segname, "__PAGEZERO", 16) != 0)
      {
        if (strncmp(segCmd64->segname, "__TEXT", 16) == 0)
        {
          *vmaddr_slide = address - segCmd64->vmaddr;
        }
        imagefilesize += segCmd64->filesize;
      }
    }
    // advance to next command
    loadCmdAddress += loadCommand->cmdsize;
  }
  free(loadcmds);
  return imagefilesize;
}

int find_off_cryptid(const char *filePath) {
    NSLog(@"[trolldecrypt] %s filePath: %s", __FUNCTION__, filePath);
    int off_cryptid = 0;
    FILE* file = fopen(filePath, "rb");
    if (!file) return 1;

    fseek(file, 0, SEEK_END);
    long fileSize = ftell(file);
    fseek(file, 0, SEEK_SET);

    char* buffer = malloc(fileSize);//new char[fileSize];
    fread(buffer, 1, fileSize, file);

    struct mach_header_64* header = (struct mach_header_64*)buffer;
    if (header->magic != MH_MAGIC_64) {
        printf("[-] error: not a valid macho file\n");
        free(buffer);
        fclose(file);
        return 2;
    }

    struct load_command* lc = (struct load_command*)((mach_vm_address_t)header + sizeof(struct mach_header_64));
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (lc->cmd == LC_ENCRYPTION_INFO || lc->cmd == LC_ENCRYPTION_INFO_64) {
            struct encryption_info_command *encryption_info = (struct encryption_info_command*) lc;
            

            off_cryptid = (mach_vm_address_t)lc + offsetof(struct encryption_info_command, cryptid) - (mach_vm_address_t)header;
            break;
        }
        lc = (struct load_command*)((mach_vm_address_t)lc + lc->cmdsize);
    }
    free(buffer);
    fclose(file);

    return off_cryptid;
}

@implementation DumpDecrypted

-(id) initWithPathToBinary:(NSString *)pathToBinary appName:(NSString *)appName appVersion:(NSString *)appVersion {
	if(!self) {
		self = [super init];
	}

	self.appName = appName;
	self.appVersion = appVersion;

	[self setAppPath:[pathToBinary stringByDeletingLastPathComponent]];
	// [self setDocPath:[NSString stringWithFormat:@"%@/Documents", NSHomeDirectory()]];
	[self setDocPath:docPath()];

	char *lastPartOfAppPath = strdup([[self appPath] UTF8String]);
	lastPartOfAppPath = strrchr(lastPartOfAppPath, '/') + 1;
	self->appDirName = strdup(lastPartOfAppPath);

	return self;
}


-(void) makeDirectories:(const char *)encryptedImageFilenameStr {
	char *appPath = (char *)[[self appPath] UTF8String];
	char *docPath = (char *)[[self docPath] UTF8String];
	char *savePtr;
	char *encryptedImagePathStr = savePtr = strdup(encryptedImageFilenameStr);
	self->filename = strdup(strrchr(encryptedImagePathStr, '/') + 1);

	// Normalize the filenames
	if(strstr(encryptedImagePathStr, "/private") == encryptedImagePathStr)
		encryptedImagePathStr += 8;
	if(strstr(appPath, "/private") == appPath)
		appPath += 8;
    
	encryptedImagePathStr += strlen(appPath) + 1; // skip over the app path
	char *p = strrchr(encryptedImagePathStr, '/');
	if(p)
		*p = '\0';
    
	
	NSFileManager *fm = [[NSFileManager alloc] init];
	NSError *err;
	char *lastPartOfAppPath = strdup(appPath); // Must free()
	lastPartOfAppPath = strrchr(lastPartOfAppPath, '/');
	lastPartOfAppPath++;
	NSString *path = [NSString stringWithFormat:@"%s/ipa/Payload/%s", docPath, lastPartOfAppPath];
	self->appDirPath = strdup([path UTF8String]);
	if(p)
		path = [NSString stringWithFormat:@"%@/%s", path, encryptedImagePathStr];

    
	if(! [fm createDirectoryAtPath:path withIntermediateDirectories:true attributes:nil error:&err]) {
	}

	free(savePtr);

	snprintf(self->decryptedAppPathStr, PATH_MAX, "%s/%s", [path UTF8String], self->filename);

	return;
}

 
-(BOOL) dumpDecryptedImage:(vm_address_t)imageAddress fileName:(const char *)encryptedImageFilenameStr image:(int)imageNum task:(vm_map_t)targetTask{
	// struct load_command *lc;
	struct encryption_info_command *eic;
	struct fat_header *fh;
	struct fat_arch *arch;
	// struct mach_header *mh;
	char buffer[1024];
	unsigned int fileoffs = 0, off_cryptid = 0, restsize;
	int i, fd, outfd, r, n;

    struct mach_header header = {0};
    vm_region_basic_info_data_64_t region_info = {0};
    if (readmem((mach_vm_offset_t*)&header, imageAddress, sizeof(struct mach_header), targetTask, &region_info))
    {
        exit(1);
    }
    
    struct load_command *lc = (struct load_command*)malloc(header.sizeofcmds);
	
	/* detect if this is a arm64 binary */
	if (header.magic == MH_MAGIC_64) {
        readmem((mach_vm_offset_t*)lc, imageAddress+sizeof(struct mach_header_64), header.sizeofcmds, targetTask, &region_info);
	} else if(header.magic == MH_MAGIC) {
        readmem((mach_vm_offset_t*)lc, imageAddress+sizeof(struct mach_header), header.sizeofcmds, targetTask, &region_info);
		
	} else {
        
		return false;
	}


    // sleep(1);exit(1);
    const struct mach_header *image_mh = &header;
	
	/* searching all load commands for an LC_ENCRYPTION_INFO load command */
	for (i=0; i<image_mh->ncmds; i++) {
		if (lc->cmd == LC_ENCRYPTION_INFO || lc->cmd == LC_ENCRYPTION_INFO_64) {
			eic = (struct encryption_info_command *)lc;
            
			const char *appFilename = strrchr(encryptedImageFilenameStr, '/');
			if(appFilename == NULL) {
                
				return false;
			}
			appFilename++;

			/* If this load command is present, but data is not crypted then exit */
			if (eic->cryptid == 0) {
                
				return false;
			}

			// Create a dir structure in ~ just like in /path/to/FooApp.app/Whatever
			[self makeDirectories:encryptedImageFilenameStr];

            //0x1518
            uint32_t aslr_slide = 0;
            get_image_size(imageAddress, targetTask, &aslr_slide);
            

			off_cryptid=find_off_cryptid(encryptedImageFilenameStr);
            
			fd = open(encryptedImageFilenameStr, O_RDONLY);
			if (fd == -1) {
                
				return false;
			}
			
			NSLog(@"[trolldecrypt] Reading header");
			n = read(fd, (void *)buffer, sizeof(buffer));
			if (n != sizeof(buffer)) {
                
				return false;
			}
            
			fh = (struct fat_header *)buffer;
			
			/* Is this a FAT file - we assume the right endianess */
			if (fh->magic == FAT_CIGAM) {
                
				arch = (struct fat_arch *)&fh[1];
				for (i=0; i<swap32(fh->nfat_arch); i++) {
					if ((image_mh->cputype == swap32(arch->cputype)) && (image_mh->cpusubtype == swap32(arch->cpusubtype))) {
						fileoffs = swap32(arch->offset);
                        
						break;
					}
					arch++;
				}
				if (fileoffs == 0) {
                    
					return false;
				}
			} else if (fh->magic == MH_MAGIC || fh->magic == MH_MAGIC_64) {
                
			} else {
                
				return false;
			}
            
			outfd = open(decryptedAppPathStr, O_RDWR|O_CREAT|O_TRUNC, 0644);
			if (outfd == -1) {
                
				return false;
			}
			
			/* calculate address of beginning of crypted data */
			n = fileoffs + eic->cryptoff;
			
			restsize = lseek(fd, 0, SEEK_END) - n - eic->cryptsize;
            
			lseek(fd, 0, SEEK_SET);
            
			
			/* first copy all the data before the encrypted data */
			char *buf = (char *)malloc((size_t)n);
			r = read(fd, buf, n);
			if(r != n) {
				NSLog(@"[trolldecrypt] Error reading start of file\n");
				return false;
			}
			r = write(outfd, buf, n);
			if(r != n) {
				NSLog(@"[trolldecrypt] Error writing start of file\n");
				return  false;
			}
			free(buf);

			/* now write the previously encrypted data */

			NSLog(@"[trolldecrypt] Dumping the decrypted data into the file (%u bytes)\n", eic->cryptsize);
            buf = (char *)malloc((size_t)eic->cryptsize);
            readmem((mach_vm_offset_t*)buf, imageAddress+eic->cryptoff, eic->cryptsize, targetTask, &region_info);
			// r = write(outfd, (unsigned char *)image_mh + eic->cryptoff, eic->cryptsize);
            r = write(outfd, buf, eic->cryptsize);
			if (r != eic->cryptsize) {
				NSLog(@"[trolldecrypt] Error writing encrypted part of file\n");
				return false;
			}
            free(buf);
            
			lseek(fd, eic->cryptsize, SEEK_CUR);
			buf = (char *)malloc((size_t)restsize);
			r = read(fd, buf, restsize);
			if (r != restsize) {
                
				return false;
			}
			r = write(outfd, buf, restsize);
			if (r != restsize) {
				NSLog(@"[trolldecrypt] Error writing rest of file\n");
				return false;
			}
			free(buf);
            

			if (off_cryptid) {
				uint32_t zero=0;
                
				if (lseek(outfd, off_cryptid, SEEK_SET) == off_cryptid) {
					if(write(outfd, &zero, 4) != 4) {
                        
					}
				} else {
                    
				}
			}
	
			close(fd);
			close(outfd);
			sync();
            // exit(1);
			
			return true;
		}
		
		lc = (struct load_command *)((unsigned char *)lc+lc->cmdsize);
        
	}
    
	return false;
}


-(void) dumpDecrypted:(pid_t)pid {

    vm_map_t targetTask = 0;
    if (task_for_pid(mach_task_self(), pid, &targetTask))
    {
        
        exit(1);
    }

    //numberOfImages
    struct task_dyld_info dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;

    if(task_info(targetTask, TASK_DYLD_INFO, (task_info_t)&dyld_info, &count) != KERN_SUCCESS) exit(1);

    mach_msg_type_number_t size = sizeof(struct dyld_all_image_infos);
    uint8_t* data = readProcessMemory(targetTask, dyld_info.all_image_info_addr, &size);
    struct dyld_all_image_infos* infos = (struct dyld_all_image_infos *) data;

    mach_msg_type_number_t size2 = sizeof(struct dyld_image_info) * infos->infoArrayCount;
    uint8_t* info_addr = readProcessMemory(targetTask, (mach_vm_address_t) infos->infoArray, &size2);
    struct dyld_image_info* info = (struct dyld_image_info*) info_addr;
        
    uint32_t numberOfImages = infos->infoArrayCount;
    mach_vm_address_t imageAddress = 0;
    const char *appPath = [[self appPath] UTF8String];
    

    for (int i = 0; i < numberOfImages; i++) {
        
        mach_msg_type_number_t size3 = PATH_MAX;
        uint8_t *fpath_addr = readProcessMemory(targetTask, (mach_vm_address_t) info[i].imageFilePath, &size3);
        
        imageAddress = (mach_vm_address_t)info[i].imageLoadAddress;
        const char *imageName = (const char *)fpath_addr;

        if(!imageName || !imageAddress)
			continue;
        

        if(strstr(imageName, appPath) != NULL) {
            
            [self dumpDecryptedImage:(const struct mach_header *)imageAddress fileName:imageName image:i task:targetTask];
		}
    }
}


-(BOOL)fileManager:(NSFileManager *)f shouldProceedAfterError:(BOOL)proceed copyingItemAtPath:(NSString *)path toPath:(NSString *)dest {
	return true;
} 

-(NSString *)IPAPath {
	return [NSString stringWithFormat:@"%@/%@_%@_decrypted.ipa", [self docPath], self.appName, self.appVersion];
}

-(void) createIPAFile:(pid_t)pid {
	NSString *IPAFile = [self IPAPath];
	NSString *appDir  = [self appPath];
	NSString *appCopyDir = [NSString stringWithFormat:@"%@/ipa/Payload/%s", [self docPath], self->appDirName];
	NSString *zipDir = [NSString stringWithFormat:@"%@/ipa", [self docPath]];
	NSFileManager *fm = [[NSFileManager alloc] init];
	NSError *err;

	[fm removeItemAtPath:IPAFile error:nil];
	[fm removeItemAtPath:appCopyDir error:nil];
	[fm createDirectoryAtPath:appCopyDir withIntermediateDirectories:true attributes:nil error:nil];

	[fm setDelegate:(id<NSFileManagerDelegate>)self];
    
	
	[fm copyItemAtPath:appDir toPath:appCopyDir error:&err];
    
	[self dumpDecrypted:pid];
    
	unlink([IPAFile UTF8String]);
	@try {
		BOOL success = [SSZipArchive createZipFileAtPath:IPAFile 
										withContentsOfDirectory:zipDir
										keepParentDirectory:NO 
										compressionLevel:1
										password:nil
										AES:NO
										progressHandler:nil
		];
        
	}
	@catch(NSException *e) {
        
	}
    
	[fm removeItemAtPath:zipDir error:nil];

    
	return;
}

@end
