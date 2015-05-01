use strict;
use warnings;
use Genome;

package Genome::Sys::Gateway;

class Genome::Sys::Gateway {
    id_by => [
        id            => { is => 'Text', doc => 'the GMS system ID of the GMS in question' },
    ],
    has => [
        hostname      => { is => 'Text' },
    ],
    has_optional => [
        id_rsa_pub    => { is => 'Text' },
        desc          => { is => 'Text' },
        ftp_detail    => { is => 'Number' },
        http_detail   => { is => 'Number' },
        ssh_detail    => { is => 'Number' },
        nfs_detail    => { is => 'Number' },
    ],
    has_calculated => [
        base_dir          => { is => 'FilesystemPath',
                              calculate_from => ['id'],
                              calculate => q|"/opt/gms/$id"|,
                              doc => 'the mount point for the system, when attached (/opt/gms/$ID)',
                            },

        is_current        => { is => 'Boolean',
                              calculate_from => ['id'],
                              calculate => q|$id eq $ENV{GENOME_SYS_ID}|,
                              doc => 'true for the current system',
                            },

        is_attached       => { is => 'Boolean', 
                              calculate_from => ['base_dir'],
                              calculate => q|-e $base_dir and not -e '$base_dir/NOT_MOUNTED'|,
                              doc => 'true when the given system is attached to the current system' 
                            },

        mount_points      => { is => 'FilesystemPath',
                              is_many => 1,
                              calculate => q|return grep { -e $_ } map { $self->_mount_point_for_protocol($_) } $self->_supported_protocols() |,
              
                            },

    ],
    data_source => { 
        #uri => "file:$tmpdir/\$rank.dat[$name\t$serial]" }
        is => 'UR::DataSource::Filesystem',
        path  => Genome::Config::get('home') . '/known-systems/$id.tsv',
        columns => ['hostname','id_rsa_pub','desc','ftp_detail','http_detail','ssh_detail','nfs_detail'],
        delimiter => "\t",
    },
};

sub _supported_protocols {
    my $self = shift;
    return ('nfs','ssh','ftp','http');
}

sub attach {
    my $self = shift;
    my $protocol = shift;

    my @protocols_to_try;
    if ($protocol) {
        @protocols_to_try = ($protocol);
    }
    else {
        @protocols_to_try = $self->_supported_protocols;
    }
    $self->debug_message("protocols to test @protocols_to_try");

    my $is_already_attached_via = $self->attached_via;

    for my $protocol (@protocols_to_try) {
        my $method = "_attach_$protocol";
        unless ($self->can($method)) {
            $self->debug_message("no support for $protocol yet...");
            next;
        }

        my $mount_point = $self->_mount_point_for_protocol($protocol);
        if (-e $mount_point) {
            $self->warning_message("mount point $mount_point exists: already mounted?");
            return 1;
        }

        $self->$method();
        
        my $base_dir_symlink = $self->base_dir;
        if (-e $base_dir_symlink) {
            rmdir $base_dir_symlink;
        }
        Genome::Sys->create_symlink($mount_point, $base_dir_symlink);  

        if ($self->is_attached) {
            $self->status_message("attached " . $self->id . " via " . $protocol);
            return 1; 
        }
        else {
            $self->error_message("error attaching " . $self->id . " via " . $protocol);
        }
    }

    if ($protocol) {
        die "no support for protocol $protocol yet...\n";
    }
    else {
        die "all protocols failed to function!\n";
    }
}

sub detach {
    my $self = shift;
    my $protocol = shift;

    my @protocols;
    if ($protocol) {
        @protocols = ($protocol);
    }
    else {
        @protocols = $self->_supported_protocols();
    }

    my @errors;
    my $count = 0;
    for my $protocol (@protocols) {
        my $mount_point = $self->_mount_point_for_protocol($protocol);
        unless (-e $mount_point) {
            next;
        }
        my $method = "_detach_$protocol";
        eval { $self->$method; };
        if ($@) {
            push @errors, $@;
        }
        eval {
            rmdir $mount_point;
            if (-e $mount_point) {
                my $msg = $? || "(unknown error)";
                push @errors, "Failed to remove mount point $mount_point: $msg"; 
            }
        };
        if ($@) {
            push @errors, $@;
        }
        $self->status_message("detached " . $self->id . " via " . $protocol);
        $count++;
    }
   
    my $base_dir = $self->base_dir;
    if (-l $base_dir and not -e $base_dir) {
        unlink $base_dir;
        if (-l $base_dir) {
            $self->warning_message("failed to remove symlink $base_dir");
        }
    }

    if (@errors) {
        die join("\n",@errors),"\n";
    }
    
    if ($count == 0) {
        if ($protocol) {
            $self->warning_message("GMS " . $self->id . " is not attached via " . $protocol);
        }
        else {
            $self->warning_message("GMS " . $self->id . " is not attached");
        }
    }

    return $count;
}

sub attached_via {
    my $self = shift;
    my $base_dir_symlink = $self->base_dir;
    if (-l $base_dir_symlink) {
        # this can be true even if -e is false
        my $path = readlink($base_dir_symlink);
        my ($protocol) = ($path =~ /.([^\.]+$)/);
        return $protocol;
    }
    elsif (-e $base_dir_symlink) {
        return 'local';
    }
    elsif (not -e $base_dir_symlink) {
        return;
    }
}

sub _protocol_for_mount_point {
    my $self = shift;
    my $base_dir = shift;
    $base_dir ||= readlink($self->base_dir);
    unless ($base_dir) {
        return 'local'; 
    }
    my ($protocol) = ($base_dir =~ /.([^\.]+$)/);
    return $protocol;
}

sub _mount_point_for_protocol {
    my $self = shift;
    my $protocol = shift;
    die "no protocol specified!" unless $protocol;
    my $base_dir_symlink = $self->base_dir;
    my $mount_point = $base_dir_symlink;
    $mount_point =~ s|/opt/gms/|/opt/gms/.|;
    $mount_point .= '.' . $protocol;
    return $mount_point;
}

##

sub _attach_ftp {
    my $self = shift;
    my $hostname = $self->hostname;
    my $ftp_detail = $self->ftp_detail;
    my $mount_point = $self->_mount_point_for_protocol('ftp');
    unless (-d $mount_point) {
        Genome::Sys->create_directory($mount_point);
    }
    my $cmd = "curlftpfs 'ftp://$hostname/$ftp_detail' '$mount_point' -o tcp_nodelay,kernel_cache,direct_io";
    Genome::Sys->shellcmd(cmd => $cmd);    

}

sub _detach_ftp {
    my $self = shift;
    my $mount_point = $self->_mount_point_for_protocol('ftp');
    my $cmd = "fusermount -u '$mount_point'";
    Genome::Sys->shellcmd(cmd => $cmd);
}

##

sub _attach_http {
    my $self = shift;
    my $hostname = $self->hostname;
    my $http_detail = $self->http_detail;
    my $mount_point = $self->_mount_point_for_protocol('http');
    unless (-d $mount_point) {
        Genome::Sys->create_directory($mount_point);
    }
    my $cmd = "curlhttpfs 'http://$hostname/$http_detail' '$mount_point' -o tcp_nodelay,kernel_cache,direct_io";
    Genome::Sys->shellcmd(cmd => $cmd);    

}

sub _detach_http {
    my $self = shift;
    my $mount_point = $self->_mount_point_for_protocol('http');
    my $cmd = "fusermount -u '$mount_point'";
    Genome::Sys->shellcmd(cmd => $cmd);
}

1;

